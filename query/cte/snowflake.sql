-- Snowflake: CTE（公共表表达式）
--
-- 参考资料:
--   [1] Snowflake SQL Reference - WITH (CTE)
--       https://docs.snowflake.com/en/sql-reference/constructs/with
--   [2] Snowflake SQL Reference - SELECT
--       https://docs.snowflake.com/en/sql-reference/sql/select

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
           username AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;

-- CTE + DML（INSERT / CREATE TABLE AS）
CREATE TABLE users_archive AS
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- CTE + QUALIFY（Snowflake 特有）
WITH ranked_users AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
)
SELECT * FROM ranked_users WHERE rn = 1;
-- 等价简写:
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

-- CTE + FLATTEN（展开半结构化数据）
WITH expanded AS (
    SELECT username, f.value::STRING AS tag
    FROM users, LATERAL FLATTEN(input => tags) f
)
SELECT tag, COUNT(*) AS cnt FROM expanded GROUP BY tag;

-- 注意：Snowflake CTE 默认内联（非物化），优化器自行决策
-- 注意：Snowflake 递归 CTE 有最大迭代次数限制
-- 注意：Snowflake 不支持 MATERIALIZED / NOT MATERIALIZED 提示
