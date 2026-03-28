# Hologres: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [Hologres Documentation - PostgreSQL 兼容](https://help.aliyun.com/document_detail/130408.html)
> - [Hologres SQL Reference - UNNEST](https://help.aliyun.com/document_detail/416498.html)
> - [Hologres SQL Reference - String Functions](https://help.aliyun.com/document_detail/102813.html)


## 示例数据


```sql
CREATE TABLE tags_csv (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');
```

## STRING_TO_ARRAY + UNNEST（推荐，兼容 PostgreSQL）


```sql
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;
```

设计分析: Hologres 继承了 PostgreSQL 的字符串拆分能力
STRING_TO_ARRAY: 字符串 → TEXT[] 数组
UNNEST: 数组 → 多行
可以直接在 SELECT 中使用 UNNEST（PostgreSQL 特有的简洁语法）

## LATERAL + UNNEST + WITH ORDINALITY（保留序号）


```sql
SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);
```

## WITH ORDINALITY 为每个元素添加序号（从 1 开始）

保留原始顺序信息

## regexp_split_to_table（正则拆分）


```sql
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;
```

regexp_split_to_table 直接将字符串拆分为多行
支持正则分隔符，如 ',\s*' 匹配逗号加可选空白
正则拆分: 自动处理逗号后空格

```sql
SELECT id, name, regexp_split_to_table(tags, ',\s*') AS tag
FROM   tags_csv;
```

## 去除空白 + 过滤空值


```sql
SELECT t.id, t.name, TRIM(s.tag) AS tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
WHERE  TRIM(s.tag) != '';
```

## STRING_TO_ARRAY('a,,b', ',') 会产生空字符串元素

需要过滤掉

## 拆分 + 聚合统计


```sql
SELECT tag, COUNT(*) AS user_count
FROM   tags_csv,
       LATERAL UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
GROUP  BY tag
ORDER  BY user_count DESC;
```

## 统计每个标签出现的次数

## 拆分 + JOIN（与其他表关联）


假设有标签定义表
CREATE TABLE tag_definitions (
tag         VARCHAR(50) PRIMARY KEY,
category    VARCHAR(50),
description TEXT
);
SELECT t.id, t.name, s.tag, d.category, d.description
FROM   tags_csv t,
LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
LEFT   JOIN tag_definitions d ON d.tag = TRIM(s.tag);

## 多列拆分


```sql
CREATE TABLE user_skills (
    id        SERIAL PRIMARY KEY,
    name      VARCHAR(100),
    languages VARCHAR(500),
    databases VARCHAR(500)
);

INSERT INTO user_skills (name, languages, databases) VALUES
    ('Alice', 'python,java', 'mysql,postgresql'),
    ('Bob',   'go,rust',     'mysql,redis');
```

## 笛卡尔积展开（2x2 = 4 行每人）

```sql
SELECT t.id, t.name, lang, db
FROM   user_skills t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.languages, ',')) AS lang
       CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(t.databases, ',')) AS db;
```

## 一一对应展开（使用序号 JOIN）

```sql
SELECT a.id, a.name, a.lang, b.db
FROM   (
    SELECT t.id, t.name, s.ordinality, s.tag AS lang
    FROM   user_skills t,
           LATERAL UNNEST(STRING_TO_ARRAY(t.languages, ','))
                  WITH ORDINALITY AS s(tag, ordinality)
) a
JOIN   (
    SELECT t.id, s.ordinality, s.tag AS db
    FROM   user_skills t,
           LATERAL UNNEST(STRING_TO_ARRAY(t.databases, ','))
                  WITH ORDINALITY AS s(tag, ordinality)
) b ON a.id = b.id AND a.ordinality = b.ordinality;
```

## Hologres 分区表中的拆分


Hologres 支持分区表，在分区表上拆分时性能可能更好
CREATE TABLE tags_csv_partitioned (
id   BIGINT,
name TEXT,
tags TEXT
) PARTITION BY LIST (name);
分区裁剪可以减少扫描的数据量
拆分操作在分区内部执行

## 横向对比与对引擎开发者的启示


## Hologres 字符串拆分特性:

完全兼容 PostgreSQL 的字符串函数
- **STRING_TO_ARRAY + UNNEST**: 标准方案
- **regexp_split_to_table**: 正则拆分
- **WITH ORDINALITY**: 保留序号
2. 与其他分析引擎对比:
- **Hologres**: STRING_TO_ARRAY + UNNEST（PostgreSQL 兼容）
- **MaxCompute**: LATERAL VIEW explode(SPLIT(...))（Hive 语法）
- **ClickHouse**: splitByChar + arrayJoin
- **BigQuery**: SPLIT + UNNEST
对引擎开发者:
兼容 PostgreSQL 生态意味着用户可以直接复用 PostgreSQL 知识
STRING_TO_ARRAY + UNNEST 是最优雅的拆分组合
regexp_split_to_table 是独有优势（其他引擎大多没有等价函数）
在分布式场景中，LATERAL 下推到存储节点可以提升性能
