-- ClickHouse: CTE（公共表表达式）
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - WITH Clause
--       https://clickhouse.com/docs/en/sql-reference/statements/select/with
--   [2] ClickHouse SQL Reference - SELECT
--       https://clickhouse.com/docs/en/sql-reference/statements/select

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

-- 标量 CTE（ClickHouse 特有，WITH 定义标量表达式）
WITH
    toDate('2024-01-01') AS start_date,
    toDate('2024-12-31') AS end_date
SELECT * FROM orders
WHERE created_at BETWEEN start_date AND end_date;

-- CTE + ARRAY JOIN
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT username, tag
FROM active_users
ARRAY JOIN tags AS tag;

-- CTE + INSERT
INSERT INTO users_archive
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

-- CTE + LIMIT BY
WITH ranked AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM ranked
ORDER BY city, age DESC
LIMIT 3 BY city;

-- 注意：ClickHouse 不支持递归 CTE（WITH RECURSIVE）
-- 注意：ClickHouse CTE 在每次引用时会被展开（内联），多次引用会重复计算
-- 注意：ClickHouse 的标量 CTE（WITH expr AS name）是独特的扩展
