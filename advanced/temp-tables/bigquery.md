# BigQuery: 临时表与临时存储

> 参考资料:
> - [1] Google Cloud - Temporary tables
>   https://cloud.google.com/bigquery/docs/multi-statement-queries#temporary_tables
> - [2] Google Cloud - Scripting
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting


 BigQuery 不支持传统的 CREATE TEMPORARY TABLE
 使用脚本中的临时表、CTE、或带过期时间的表

## 脚本中的临时表（Multi-statement queries）


在脚本块中创建临时表

```sql
CREATE TEMP TABLE temp_active_users AS
SELECT id, username, email
FROM `project.dataset.users`
WHERE status = 1;

```

使用临时表

```sql
SELECT * FROM temp_active_users WHERE username LIKE 'a%';

```

 临时表在脚本结束时自动删除

## 完整脚本示例


```sql
DECLARE total_users INT64;

CREATE TEMP TABLE temp_stats AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM `project.dataset.orders`
WHERE order_date >= '2024-01-01'
GROUP BY user_id;

SET total_users = (SELECT COUNT(*) FROM temp_stats);

SELECT t.user_id, u.username, t.total_amount
FROM temp_stats t
JOIN `project.dataset.users` u ON t.user_id = u.id
WHERE t.total_amount > 1000
ORDER BY t.total_amount DESC;

```

## CTE（推荐方式）


```sql
WITH active_users AS (
    SELECT * FROM `project.dataset.users` WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username,
           COUNT(o.id) AS order_count,
           SUM(o.amount) AS total_amount
    FROM active_users u
    LEFT JOIN `project.dataset.orders` o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders
WHERE order_count > 5
ORDER BY total_amount DESC;

```

递归 CTE

```sql
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM `project.dataset.categories`
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, t.depth + 1
    FROM `project.dataset.categories` c
    JOIN tree t ON c.parent_id = t.id
)
SELECT * FROM tree;

```

## 带过期时间的表（替代临时表）


创建带有过期时间的表

```sql
CREATE TABLE `project.dataset.staging_data`
(
    id INT64,
    data STRING
)
OPTIONS (
    expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
);

```

修改过期时间

```sql
ALTER TABLE `project.dataset.staging_data`
SET OPTIONS (
    expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
);

```

## 查询结果缓存（隐式临时存储）


 BigQuery 自动缓存查询结果（24 小时）
 相同查询不会重新计算，也不收费

 通过匿名数据集存储临时结果
 查询结果自动存储在 _script* 或匿名数据集中

## SESSION 临时表（BigQuery 会话模式）


在交互式会话中（如 BigQuery Studio）
临时表在会话期间持续存在

注意：BigQuery 脚本中的 CREATE TEMP TABLE 在脚本结束时自动删除
注意：CTE 是 BigQuery 中最常用的临时数据组织方式
注意：带过期时间的表可以作为持久化的临时存储
注意：查询结果缓存提供隐式的临时存储（24 小时）
注意：BigQuery 按扫描量计费，临时表可以减少重复扫描

