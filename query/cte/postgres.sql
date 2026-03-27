-- PostgreSQL: CTE（8.4+）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - WITH Queries (CTEs)
--       https://www.postgresql.org/docs/current/queries-with.html
--   [2] PostgreSQL Documentation - SELECT
--       https://www.postgresql.org/docs/current/sql-select.html

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

-- 递归 CTE
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;

-- 递归：层级结构
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           username::TEXT AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- 递归：图遍历（检测循环）
WITH RECURSIVE search AS (
    SELECT id, username, manager_id, ARRAY[id] AS path, false AS cycle
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, s.path || u.id, u.id = ANY(s.path)
    FROM users u JOIN search s ON u.manager_id = s.id
    WHERE NOT s.cycle
)
SELECT * FROM search;

-- 14+: SEARCH 和 CYCLE 子句
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SEARCH DEPTH FIRST BY id SET ordercol
CYCLE id SET is_cycle USING path
SELECT * FROM org_tree;

-- CTE + DML（可写 CTE，9.1+）
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

-- 12+: MATERIALIZED / NOT MATERIALIZED
-- 12 之前 CTE 总是物化的（优化围栏），12+ 可以内联
WITH active_users AS MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users;

WITH active_users AS NOT MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users;
