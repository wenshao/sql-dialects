-- SQLite: CTE（3.8.3+）
--
-- 参考资料:
--   [1] SQLite Documentation - WITH (CTE)
--       https://www.sqlite.org/lang_with.html
--   [2] SQLite Documentation - SELECT
--       https://www.sqlite.org/lang_select.html

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

-- 递归 CTE（3.8.3+）
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

-- 3.34.0+: MATERIALIZED / NOT MATERIALIZED
WITH active_users AS MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users;

-- CTE + DML（3.35.0+）
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
