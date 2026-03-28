# DuckDB: 数据去重

> 参考资料:
> - [DuckDB Documentation - Window Functions](https://duckdb.org/docs/sql/window_functions)
> - [DuckDB Documentation - QUALIFY](https://duckdb.org/docs/sql/query_syntax/qualify)
> - [DuckDB Documentation - DISTINCT ON](https://duckdb.org/docs/sql/query_syntax/select#distinct-on-clause)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 示例数据上下文

假设表结构:
  users(user_id INTEGER, email VARCHAR, username VARCHAR, created_at TIMESTAMP)

## 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

```

## QUALIFY 去重（推荐方式）


```sql
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

```

## DISTINCT ON（DuckDB 支持 PostgreSQL 语法）


```sql
SELECT DISTINCT ON (email)
       user_id, email, username, created_at
FROM users
ORDER BY email, created_at DESC;

```

## 传统 ROW_NUMBER 方式


```sql
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

```

## 删除重复数据


```sql
DELETE FROM users
WHERE rowid NOT IN (
    SELECT MIN(rowid)
    FROM users
    GROUP BY email
);

```

CTAS 方式
```sql
CREATE OR REPLACE TABLE users AS
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

```

## 直接从文件去重


从 Parquet 文件直接去重查询
```sql
SELECT user_id, email, username, created_at
FROM read_parquet('users.parquet')
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

```

从 CSV 文件去重并写入新文件
```sql
COPY (
    SELECT DISTINCT ON (email)
           user_id, email, username, created_at
    FROM read_csv_auto('users.csv')
    ORDER BY email, created_at DESC
) TO 'users_deduped.parquet' (FORMAT PARQUET);

```

## 近似去重


```sql
SELECT approx_count_distinct(email) AS approx_distinct
FROM users;

```

## DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

```

## 性能考量


DuckDB 同时支持 QUALIFY 和 DISTINCT ON
列式引擎，去重操作自动向量化
直接从 Parquet/CSV 文件去重，无需导入
无需手动创建索引
