# Spanner: 字符串拆分

> 参考资料:
> - [Cloud Spanner SQL Reference - SPLIT](https://cloud.google.com/spanner/docs/reference/standard-sql/string_functions#split)
> - [Cloud Spanner SQL Reference - UNNEST](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#unnest)
> - [Cloud Spanner SQL Reference - Array Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/array_functions)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 示例数据


```sql
CREATE TABLE tags_csv (
    id   INT64 NOT NULL,
    name STRING(100),
    tags STRING(500)
) PRIMARY KEY (id);

```

DML 插入数据（DDL 和 DML 需分开执行）
INSERT INTO tags_csv (id, name, tags) VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

## SPLIT + UNNEST（最简洁的方案）


```sql
SELECT id, name, tag
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag;

```

**设计分析:** 两步组合（与 BigQuery 完全一致）
  SPLIT(tags, ','): 字符串 → ARRAY（'a,b,c' → ['a','b','c']）
  UNNEST(): 数组 → 多行（3 个元素 → 3 行）
  Spanner 和 BigQuery 共享 GoogleSQL 语法

## 带序号的展开


```sql
SELECT id, name, tag, pos
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag WITH OFFSET AS pos
ORDER  BY id, pos;

```

WITH OFFSET 为数组元素添加序号（从 0 开始）
适用于需要知道"第几个元素"的场景

## 去除空白 + 过滤空值


```sql
SELECT id, name, TRIM(tag) AS tag
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag
WHERE  TRIM(tag) != '';

```

SPLIT 可能包含空白: 'a, b , c' → ['a',' b ',' c']
TRIM 去除前后空白

## 拆分 + 聚合统计


```sql
SELECT tag, COUNT(*) AS user_count
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag
GROUP  BY tag
ORDER  BY user_count DESC;

```

统计每个标签被多少用户使用

## 拆分 + JOIN（与其他表关联）


假设有标签定义表
CREATE TABLE tag_definitions (
    tag        STRING(50) NOT NULL,
    category   STRING(50),
    description STRING(200)
) PRIMARY KEY (tag);

SELECT t.id, t.name, s.tag, d.category
FROM   tags_csv t,
       UNNEST(SPLIT(t.tags, ',')) AS s,
       tag_definitions d
WHERE  s.tag = d.tag;

## 正则拆分


SPLIT 支持分隔符，但不如正则灵活
需要复杂拆分时，可使用 REGEXP_EXTRACT_ALL:

```sql
SELECT id, name, word
FROM   tags_csv,
       UNNEST(REGEXP_EXTRACT_ALL(tags, r'[^,]+')) AS word;

```

REGEXP_EXTRACT_ALL: 使用正则提取所有匹配项
r'[^,]+' 匹配非逗号字符序列，等同于按逗号拆分

## 多列拆分


CREATE TABLE user_skills (
    id        INT64 NOT NULL,
    name      STRING(100),
    languages STRING(500),
    databases STRING(500)
) PRIMARY KEY (id);

SELECT id, name, lang, db
FROM   user_skills,
       UNNEST(SPLIT(languages, ',')) AS lang
       CROSS JOIN UNNEST(SPLIT(databases, ',')) AS db;

**注意:** CROSS JOIN 产生笛卡尔积
如果需要一一对应，使用 WITH OFFSET + JOIN

## LATERAL 关联查询


```sql
SELECT t.id, t.name, s.tag, s.pos
FROM   tags_csv t,
       LATERAL (
         SELECT tag, pos
         FROM   UNNEST(SPLIT(t.tags, ',')) AS tag WITH OFFSET AS pos
       ) s
ORDER  BY t.id, s.pos;

```

LATERAL 允许子查询引用外表列
与直接 UNNEST 效果相同，但可以添加额外逻辑

## 横向对比与对引擎开发者的启示


## Spanner 字符串拆分特性:

  SPLIT + UNNEST: GoogleSQL 标准模式
  WITH OFFSET: 保留位置信息
  REGEXP_EXTRACT_ALL: 正则提取
  LATERAL: 灵活关联查询

## 与其他 GoogleSQL 引擎对比:

  Spanner:  SPLIT + UNNEST（与 BigQuery 语法相同）
  BigQuery: SPLIT + UNNEST
  区别: BigQuery 的 REGEXP_EXTRACT_ALL 返回 ARRAY<STRING>
        Spanner 的正则函数行为一致

**对引擎开发者:**
  SPLIT + UNNEST 是最简洁优雅的拆分方案
  分割和展开分离 → 组合灵活 → 中间结果可复用
  WITH OFFSET 是保留元素位置的关键特性
  GoogleSQL 的统一语法降低了在 Spanner/BigQuery 间的学习成本
