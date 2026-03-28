# IBM Db2: 数据去重策略（Deduplication）

> 参考资料:
> - [IBM Db2 Documentation - MERGE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-merge)
> - ============================================================
> - 示例数据上下文
> - ============================================================
> - 假设表结构:
> - users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)
> - ============================================================
> - 1. 查找重复数据
> - ============================================================

```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

SELECT u.*
FROM users u
JOIN (
    SELECT email FROM users GROUP BY email HAVING COUNT(*) > 1
) dup ON u.email = dup.email
ORDER BY u.email, u.created_at;
```

## 保留每组一行（ROW_NUMBER 方式）


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


## 标准 DELETE 方式

```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT keep_id FROM (
        SELECT MAX(user_id) AS keep_id
        FROM users
        GROUP BY email
    ) keepers
);
```

## CTAS 方式（创建去重后的新表）

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
) ranked
WHERE rn = 1;
```

## MERGE（防止重复插入）


```sql
MERGE INTO users target
USING new_users source
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET target.username = source.username, target.created_at = source.created_at
WHEN NOT MATCHED THEN
    INSERT (email, username, created_at) VALUES (source.email, source.username, source.created_at);
```

## DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

SELECT email, COUNT(*) AS cnt, MAX(created_at) AS latest
FROM users
GROUP BY email;
```

## 近似去重（APPROX_COUNT_DISTINCT）


```sql
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct_emails
FROM users;
```

## 性能考量


## Db2 的 MERGE 语句功能强大

OLAP 函数支持非常早

```sql
CREATE INDEX idx_users_email ON users (email);
```
