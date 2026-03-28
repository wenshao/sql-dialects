# DuckDB: 临时表

> 参考资料:
> - [DuckDB Documentation - CREATE TABLE](https://duckdb.org/docs/sql/statements/create_table)
> - [DuckDB Documentation - WITH (CTE)](https://duckdb.org/docs/sql/query_syntax/with)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## CREATE TEMPORARY TABLE


```sql
CREATE TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR,
    email VARCHAR
);

CREATE TEMP TABLE temp_results AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

```

## 使用临时表


```sql
INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;

DROP TABLE IF EXISTS temp_users;

```

## CTE（高度优化）


DuckDB 对 CTE 有很好的优化
```sql
WITH active AS (
    SELECT * FROM users WHERE status = 1
),
order_stats AS (
    SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
    FROM orders GROUP BY user_id
)
SELECT a.username, o.total, o.cnt
FROM active a JOIN order_stats o ON a.id = o.user_id
ORDER BY o.total DESC;

```

递归 CTE
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 1000
)
SELECT * FROM nums;

```

## CREATE TABLE AS（CTAS）


```sql
CREATE TABLE staging AS SELECT * FROM read_csv_auto('data.csv');

```

使用后删除
```sql
DROP TABLE staging;

```

## 内存表（默认行为）


DuckDB 默认将数据存储在内存中
也支持持久化到磁盘文件

**注意:** DuckDB 临时表与普通表性能差异不大
**注意:** CTE 在 DuckDB 中高度优化，是推荐的临时数据方式
**注意:** DuckDB 支持直接从文件（CSV/Parquet/JSON）查询
**注意:** 内存模式下所有表本质上都是"临时"的
