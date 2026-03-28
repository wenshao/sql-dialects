-- Apache Doris: CTE
--
-- 参考资料:
--   [1] Doris Documentation - WITH
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. 基本 CTE
-- ============================================================
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- 多个 CTE
WITH active AS (SELECT * FROM users WHERE status = 1),
user_orders AS (SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total FROM orders GROUP BY user_id)
SELECT u.username, o.cnt, o.total FROM active u JOIN user_orders o ON u.id = o.user_id;

-- CTE 引用前面的 CTE
WITH base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;

-- ============================================================
-- 2. 递归 CTE (2.1+)
-- ============================================================
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- 设计分析:
--   Doris 2.1+ 支持递归 CTE——这是层级查询的标准方案。
--   对比: StarRocks 也支持递归 CTE(更早)。
--   对比: ClickHouse 不支持递归 CTE(用数组函数替代)。

-- ============================================================
-- 3. CTE + DML
-- ============================================================
INSERT INTO users_archive
WITH inactive AS (SELECT * FROM users WHERE last_login < '2023-01-01')
SELECT * FROM inactive;

-- ============================================================
-- 4. CTE + 窗口函数
-- ============================================================
WITH monthly_sales AS (
    SELECT DATE_FORMAT(order_date, '%Y-%m') AS month, SUM(amount) AS total
    FROM orders GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT month, total, total - LAG(total) OVER (ORDER BY month) AS growth
FROM monthly_sales;

-- CTE 默认内联(不物化)。优化器决定是否物化。
