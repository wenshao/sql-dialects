# Trino: 数据去重

> 参考资料:
> - [Trino Documentation - Window Functions](https://trino.io/docs/current/functions/window.html)
> - [Trino Documentation - MERGE](https://trino.io/docs/current/sql/merge.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

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

## 保留每组一行


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


MERGE 方式（Trino 支持部分连接器的 MERGE）
```sql
MERGE INTO users target
USING (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    ) WHERE rn > 1
) dups
ON target.user_id = dups.user_id
WHEN MATCHED THEN DELETE;

```

CTAS 方式
```sql
CREATE TABLE users_clean AS
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) WHERE rn = 1;

```

## 近似去重


```sql
SELECT approx_distinct(email) AS approx_distinct_emails
FROM users;

```

## DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

```

## 性能考量


Trino 是 MPP 查询引擎
approx_distinct 使用 HyperLogLog
MERGE 支持取决于连接器（Hive, Iceberg, Delta Lake）
**注意:** Trino 不支持 QUALIFY
