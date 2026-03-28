# Amazon Redshift: 数据去重策略（Deduplication）

> 参考资料:
> - [Redshift Documentation - Window Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_Window_functions.html)
> - [Redshift Documentation - QUALIFY](https://docs.aws.amazon.com/redshift/latest/dg/r_QUALIFY_clause.html)


## 示例数据上下文

假设表结构:
users(user_id INT, email VARCHAR(255), username VARCHAR(64), created_at TIMESTAMP)

## 1. 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;
```


## 2. QUALIFY 去重


```sql
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;
```


传统 ROW_NUMBER 方式
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


## 3. 删除重复数据


CTAS + DROP + RENAME（Redshift 推荐方式）
```sql
CREATE TABLE users_clean AS
SELECT user_id, email, username, created_at
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) WHERE rn = 1;

DROP TABLE users;
ALTER TABLE users_clean RENAME TO users;
```


DELETE 方式
```sql
DELETE FROM users
WHERE user_id NOT IN (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (
                   PARTITION BY email
                   ORDER BY created_at DESC
               ) AS rn
        FROM users
    ) WHERE rn = 1
);
```


## 4. 近似去重


```sql
SELECT APPROXIMATE COUNT(DISTINCT email) AS approx_distinct
FROM users;
```


## 5. DISTINCT vs GROUP BY


```sql
SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;
```


## 6. 性能考量


CTAS + DROP + RENAME 比 DELETE 更高效（避免大量 DML）
DISTKEY(email) 使去重操作本地执行
SORTKEY(email) 加速 GROUP BY
APPROXIMATE COUNT(DISTINCT) 使用 HyperLogLog
