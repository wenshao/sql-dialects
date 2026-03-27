-- Trino: CTE（公共表表达式）
--
-- 参考资料:
--   [1] Trino - SELECT (WITH Clause)
--       https://trino.io/docs/current/sql/select.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

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
    SELECT id, username, manager_id, 0 AS level,
           CAST(username AS VARCHAR) AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- CTE + UNNEST
WITH tag_list AS (
    SELECT username, tag
    FROM users
    CROSS JOIN UNNEST(tags) AS t(tag)
)
SELECT tag, COUNT(*) AS cnt
FROM tag_list
GROUP BY tag ORDER BY cnt DESC;

-- CTE + INSERT（WITH 子句作为 INSERT 查询部分）
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- CTE + LATERAL
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, latest.amount
FROM active_users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

-- 注意：Trino CTE 语法高度符合 SQL 标准
-- 注意：Trino CTE 会被内联（非物化），多次引用可能重复计算
-- 注意：Trino 不支持 MATERIALIZED / NOT MATERIALIZED 提示
-- 注意：递归 CTE 的性能取决于底层连接器
