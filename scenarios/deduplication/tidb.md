# TiDB: 数据去重

> 参考资料:
> - [TiDB Documentation - Window Functions](https://docs.pingcap.com/tidb/stable/window-functions)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 示例数据上下文

假设表结构:
  users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)

## 查找重复数据


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


DELETE JOIN 方式
```sql
DELETE u1
FROM users u1
JOIN users u2
  ON u1.email = u2.email
  AND u1.user_id < u2.user_id;


```

标准 DELETE 方式
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

CTAS 方式（创建去重后的新表）
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

## 性能考量


TiDB 兼容 MySQL 语法
DELETE JOIN 可用
```sql
CREATE INDEX idx_users_email ON users (email);

```
