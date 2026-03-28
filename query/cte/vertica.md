# Vertica: CTE（公共表表达式）

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


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
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```


递归：层级结构
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```


递归：路径构建
```sql
WITH RECURSIVE category_path AS (
    SELECT id, name, parent_id, name::VARCHAR(4000) AS path
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, cp.path || ' > ' || c.name
    FROM categories c JOIN category_path cp ON c.parent_id = cp.id
)
SELECT * FROM category_path;
```


CTE + INSERT
```sql
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;
```


CTE + MERGE
```sql
WITH new_data AS (
    SELECT id, username, email, age FROM staging_users
)
MERGE INTO users t
USING new_data s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);
```


CTE + 分析函数
```sql
WITH monthly_sales AS (
    SELECT DATE_TRUNC('month', order_date) AS month,
           SUM(amount) AS total
    FROM orders
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT month, total,
    total - LAG(total) OVER (ORDER BY month) AS growth,
    total / NULLIF(LAG(total) OVER (ORDER BY month), 0) - 1 AS growth_rate
FROM monthly_sales;
```


注意：Vertica 支持标准 CTE 语法
注意：支持递归 CTE
注意：CTE 可以与 INSERT / MERGE 结合
注意：CTE 被优化器自动决定是否物化
