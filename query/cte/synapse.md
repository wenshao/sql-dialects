# Azure Synapse: CTE（公共表表达式）

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


基本 CTE
```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```


多个 CTE
```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;
```


CTE 引用前面的 CTE
```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;
```


递归 CTE
```sql
WITH nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums
OPTION (MAXRECURSION 100);                   -- 设置最大递归次数（默认 100）
```


递归：层级结构
```sql
WITH org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS NVARCHAR(MAX)) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path + N' > ' + u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree
OPTION (MAXRECURSION 0);                     -- 0 = 无限制
```


CTE + CTAS（推荐模式）
```sql
CREATE TABLE users_archive
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;
```


CTE + INSERT
```sql
WITH new_data AS (
    SELECT 'alice' AS username, N'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT username, email, age FROM new_data;
```


CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```


CTE + UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE u
SET u.status = 2
FROM users u
INNER JOIN vip v ON u.id = v.user_id;
```


CTE + 窗口函数
```sql
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
)
SELECT * FROM ranked WHERE rn = 1;
```


多层 CTE 嵌套分析
```sql
WITH
daily_sales AS (
    SELECT order_date, SUM(amount) AS daily_total
    FROM orders GROUP BY order_date
),
weekly_avg AS (
    SELECT order_date, daily_total,
        AVG(daily_total) OVER (ORDER BY order_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7day
    FROM daily_sales
)
SELECT * FROM weekly_avg WHERE daily_total > avg_7day * 1.5;
```


注意：Synapse 中递归 CTE 不需要 RECURSIVE 关键字
注意：OPTION (MAXRECURSION n) 控制递归深度（默认 100）
注意：CTE 是内联的，多次引用会多次计算
注意：CTE + CTAS 是 Synapse 中常见的数据转换模式
注意：Serverless 池也支持 CTE
