-- Apache Doris: CTE（公共表表达式）
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 基本 CTE
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE
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

-- CTE 引用前面的 CTE
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;

-- 递归 CTE（2.1+）
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- 递归：层级结构
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- CTE + INSERT
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- CTE + 聚合
WITH monthly_sales AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month,
           SUM(amount) AS total
    FROM orders
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month, total,
    total - LAG(total) OVER (ORDER BY month) AS growth
FROM monthly_sales;

-- CTE + JOIN
WITH vip_users AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
SELECT u.username, v.total
FROM users u JOIN vip_users v ON u.id = v.user_id;

-- 注意：Doris 兼容 MySQL 协议，CTE 语法与 MySQL 8.0 类似
-- 注意：Doris 2.1+ 支持递归 CTE
-- 注意：CTE 默认内联，优化器自行决策是否物化
