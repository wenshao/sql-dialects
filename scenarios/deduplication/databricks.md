# Databricks (Spark SQL): 数据去重策略（Deduplication）

> 参考资料:
> - [Databricks SQL Reference - QUALIFY](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-qry-select-qualify.html)
> - [Databricks Documentation - MERGE INTO](https://docs.databricks.com/sql/language-manual/delta-merge-into.html)


## 示例数据上下文

假设表结构（Delta 表）:
users(user_id INT, email STRING, username STRING, created_at TIMESTAMP)

## 1. 查找重复数据


```sql
SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;
```


## 2. QUALIFY 去重（Databricks Runtime 12.2+）


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


## 3. 删除重复（Delta 表 MERGE）


MERGE 方式删除重复
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


CTAS 重建（推荐方式）
```sql
CREATE OR REPLACE TABLE users AS
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;
```


## 4. Delta 表 MERGE（防止重复插入）


```sql
MERGE INTO users target
USING new_users source
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET target.username = source.username, target.created_at = source.created_at
WHEN NOT MATCHED THEN
    INSERT (email, username, created_at) VALUES (source.email, source.username, source.created_at);
```


## 5. dropDuplicates（Spark DataFrame API，非 SQL）


spark.table("users").dropDuplicates(["email"])

## 6. 近似去重


```sql
SELECT approx_count_distinct(email) AS approx_distinct
FROM users;
```


## 7. 性能考量


Delta MERGE 支持事务性去重
QUALIFY 是 Databricks 推荐方式
```sql
OPTIMIZE users ZORDER BY (email);
-- Photon 引擎自动优化
```
