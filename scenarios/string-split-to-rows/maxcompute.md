# MaxCompute (ODPS): 将分隔字符串拆分为多行

> 参考资料:
> - [1] MaxCompute SQL - LATERAL VIEW
>   https://help.aliyun.com/zh/maxcompute/user-guide/lateral-view
> - [2] MaxCompute SQL - SPLIT
>   https://help.aliyun.com/zh/maxcompute/user-guide/string-functions


## 1. LATERAL VIEW EXPLODE + SPLIT（核心方案）


```sql
CREATE TABLE IF NOT EXISTS tags_csv (id BIGINT, name STRING, tags STRING);
```

tags: 'python,java,sql'


```sql
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;

```

 三步组合:
   SPLIT('python,java,sql', ',') → ARRAY['python','java','sql']
   EXPLODE(array) → 3 行: 'python', 'java', 'sql'
   LATERAL VIEW: 将展开结果与原表行关联

## 2. POSEXPLODE: 带位置序号


```sql
SELECT t.id, t.name, pos, tag
FROM tags_csv t
LATERAL VIEW POSEXPLODE(SPLIT(t.tags, ',')) exploded AS pos, tag;
```

 pos 从 0 开始

## 3. 去除空白 + 过滤空值


```sql
SELECT t.id, t.name, TRIM(tag) AS tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag
WHERE TRIM(tag) != '';

```

正则分隔（自动去除空格）

```sql
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',\\s*')) exploded AS tag;

```

## 4. 拆分后聚合统计


```sql
SELECT tag, COUNT(*) AS user_count
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag
GROUP BY tag ORDER BY user_count DESC;

```

## 5. 多列拆分（笛卡尔积 vs 一一对应）


笛卡尔积（两列独立展开）

```sql
SELECT t.id, lang, db
FROM user_skills t
LATERAL VIEW EXPLODE(SPLIT(t.languages, ',')) l AS lang
LATERAL VIEW EXPLODE(SPLIT(t.databases, ',')) d AS db;
```

2 x 2 = 4 行

一一对应（用 posexplode + 位置匹配）

```sql
SELECT a.id, a.lang, b.db
FROM (
    SELECT t.id, pos, lang
    FROM user_skills t
    LATERAL VIEW POSEXPLODE(SPLIT(t.languages, ',')) l AS pos, lang
) a
JOIN (
    SELECT t.id, pos, db
    FROM user_skills t
    LATERAL VIEW POSEXPLODE(SPLIT(t.databases, ',')) d AS pos, db
) b ON a.id = b.id AND a.pos = b.pos;
```

 2 x 1 = 2 行（一一对应）

## 6. 横向对比与引擎开发者启示


 字符串拆分:
MaxCompute: LATERAL VIEW EXPLODE(SPLIT(...))    | Hive: 相同
BigQuery:   UNNEST(SPLIT(...))                  | PostgreSQL: UNNEST(STRING_TO_ARRAY(...))
Snowflake:  LATERAL FLATTEN(INPUT => SPLIT(...))| Presto: CROSS JOIN UNNEST(SPLIT(...))

 对引擎开发者:
1. SPLIT + EXPLODE 组合是字符串拆分的标准方案 — 应高效实现

2. POSEXPLODE 是有价值的增强: 保留位置信息用于一一对应

3. 多 LATERAL VIEW 的笛卡尔积行为需要文档明确说明

4. BigQuery 的 UNNEST(SPLIT()) 是最简洁的语法 — 值得参考

5. 正则分隔符支持（SPLIT(',\\s*')）减少了后续 TRIM 操作

