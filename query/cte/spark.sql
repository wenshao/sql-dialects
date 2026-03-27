-- Spark SQL: CTE (Common Table Expressions) (Spark 2.1+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Basic CTE
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;

-- Multiple CTEs
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

-- CTE referencing another CTE
WITH
base AS (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
),
ranked AS (
    SELECT city, cnt, ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn
    FROM base
)
SELECT * FROM ranked WHERE rn <= 5;

-- CTE with aggregation
WITH daily_sales AS (
    SELECT
        CAST(order_time AS DATE) AS order_date,
        SUM(amount) AS daily_total
    FROM orders
    GROUP BY CAST(order_time AS DATE)
)
SELECT order_date, daily_total,
    SUM(daily_total) OVER (ORDER BY order_date) AS running_total
FROM daily_sales;

-- CTE with UNION
WITH combined AS (
    SELECT username, email, 'active' AS source FROM active_users
    UNION ALL
    SELECT username, email, 'inactive' AS source FROM inactive_users
)
SELECT * FROM combined;

-- CTE used in INSERT (Spark 3.0+)
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- CTE used in CREATE TABLE AS
CREATE TABLE top_cities AS
WITH city_stats AS (
    SELECT city, COUNT(*) AS user_count, AVG(age) AS avg_age
    FROM users
    GROUP BY city
)
SELECT * FROM city_stats WHERE user_count > 100;

-- CTE with JOIN
WITH high_spenders AS (
    SELECT user_id, SUM(amount) AS total_spent
    FROM orders
    GROUP BY user_id
    HAVING SUM(amount) > 10000
)
SELECT u.username, h.total_spent
FROM users u
JOIN high_spenders h ON u.id = h.user_id
ORDER BY h.total_spent DESC;

-- CTE with LATERAL VIEW
WITH user_data AS (
    SELECT id, username, tags FROM users WHERE tags IS NOT NULL
)
SELECT username, tag
FROM user_data
LATERAL VIEW EXPLODE(tags) t AS tag;

-- Note: No recursive CTEs (Spark does not support WITH RECURSIVE)
-- Note: No writable CTEs (DML inside CTE body, e.g., WITH d AS (DELETE ... RETURNING *))
-- Note: No MATERIALIZED / NOT MATERIALIZED hints
-- Note: For recursive-like operations, use iterative DataFrame API or
--       GraphFrames library
-- Note: Spark may inline or cache CTE results based on optimizer decisions
-- Note: CTE in INSERT INTO supported from Spark 3.0+
