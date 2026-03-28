# DuckDB: 字符串拆分

> 参考资料:
> - [DuckDB Documentation - String Functions](https://duckdb.org/docs/sql/functions/char.html)
> - [DuckDB Documentation - UNNEST](https://duckdb.org/docs/sql/query_syntax/unnest)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 示例数据

```sql
CREATE TABLE tags_csv AS
SELECT 1 AS id, 'Alice' AS name, 'python,java,sql' AS tags
UNION ALL SELECT 2, 'Bob',   'go,rust'
UNION ALL SELECT 3, 'Carol', 'sql,python,javascript,typescript';

```

## 方法 1: UNNEST + STRING_SPLIT（推荐）

```sql
SELECT id, name, UNNEST(STRING_SPLIT(tags, ',')) AS tag
FROM   tags_csv;

```

## 方法 2: UNNEST + STRING_SPLIT_REGEX

```sql
SELECT id, name, UNNEST(STRING_SPLIT_REGEX(tags, ',\s*')) AS tag
FROM   tags_csv;

```

## 方法 3: UNNEST 带序号（generate_subscripts）

```sql
SELECT id, name, tag, pos
FROM   tags_csv,
       LATERAL (
           SELECT UNNEST(STRING_SPLIT(tags, ',')) AS tag,
                  GENERATE_SERIES(1, LEN(STRING_SPLIT(tags, ','))) AS pos
       );

```

## 方法 4: 递归 CTE

```sql
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           STRING_SPLIT(tags, ',')[1] AS tag,
           tags AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           STRING_SPLIT(remaining, ',')[pos + 1],
           remaining,
           pos + 1
    FROM   split_cte
    WHERE  pos < LEN(STRING_SPLIT(remaining, ','))
)
SELECT id, name, tag, pos FROM split_cte WHERE tag IS NOT NULL ORDER BY id, pos;

```
