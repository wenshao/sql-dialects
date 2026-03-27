-- CockroachDB: 临时表与临时存储
--
-- 参考资料:
--   [1] CockroachDB Documentation - Temporary Tables
--       https://www.cockroachlabs.com/docs/stable/temporary-tables.html
--   [2] CockroachDB Documentation - WITH (CTE)
--       https://www.cockroachlabs.com/docs/stable/common-table-expressions.html

-- ============================================================
-- CREATE TEMPORARY TABLE（20.1+）
-- ============================================================

-- 需要先启用临时表
SET experimental_enable_temp_tables = on;

CREATE TEMPORARY TABLE temp_users (
    id INT PRIMARY KEY,
    username STRING,
    email STRING
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- ============================================================
-- 临时表特性
-- ============================================================

-- 1. 会话级别，会话结束时自动删除
-- 2. 存储在特殊的临时 schema 中
-- 3. 只对当前会话可见
-- 4. 支持索引

CREATE INDEX ON temp_users (username);

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;

DROP TABLE IF EXISTS temp_users;

-- ============================================================
-- CTE（推荐方式）
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username, COUNT(o.id) AS order_count
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;

-- 可写 CTE（INSERT/UPDATE/DELETE + RETURNING）
WITH deleted AS (
    DELETE FROM orders WHERE status = 'cancelled' RETURNING *
)
INSERT INTO cancelled_orders SELECT * FROM deleted;

-- 递归 CTE
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, t.depth + 1
    FROM categories c JOIN tree t ON c.parent_id = t.id
)
SELECT * FROM tree;

-- 注意：临时表需要设置 experimental_enable_temp_tables = on
-- 注意：CTE 是 CockroachDB 中更常用的临时数据方式
-- 注意：CockroachDB 支持可写 CTE（WITH ... DELETE/UPDATE RETURNING）
-- 注意：临时表存储在分布式 KV 存储中
