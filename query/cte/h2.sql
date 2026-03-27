-- H2: CTE（公共表表达式）
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

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

-- 递归 CTE
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
WITH new_data AS (
    SELECT * FROM users WHERE created_at > '2024-01-01'
)
INSERT INTO users_archive SELECT * FROM new_data;

-- CTE + UPDATE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0 WHERE id IN (SELECT id FROM inactive);

-- CTE + DELETE
WITH old_users AS (
    SELECT id FROM users WHERE created_at < '2020-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM old_users);

-- 注意：H2 支持标准 CTE 和递归 CTE
-- 注意：CTE 可以与 INSERT、UPDATE、DELETE 配合使用
-- 注意：递归 CTE 有默认迭代次数限制
-- 注意：CTE 在 H2 的所有兼容模式中都可用
