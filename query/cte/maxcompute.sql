-- MaxCompute: CTE（公共表表达式）
--
-- 参考资料:
--   [1] MaxCompute SQL - CTE
--       https://help.aliyun.com/zh/maxcompute/user-guide/cte
--   [2] MaxCompute SQL - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select

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

-- CTE + LATERAL VIEW
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, tag
FROM active_users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- CTE + INSERT
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
INSERT INTO TABLE users_archive
SELECT * FROM inactive;

-- CTE + MAPJOIN hint
WITH small_table AS (
    SELECT * FROM roles WHERE active = 1
)
SELECT /*+ MAPJOIN(s) */ u.username, s.role_name
FROM users u
JOIN small_table s ON u.role_id = s.id;

-- 注意：MaxCompute 不支持递归 CTE（WITH RECURSIVE）
-- 注意：MaxCompute CTE 会被优化器内联或物化，用户无法控制
-- 注意：MaxCompute CTE 嵌套层数有限制
