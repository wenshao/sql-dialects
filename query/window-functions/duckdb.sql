-- DuckDB: Window Functions (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- ROW_NUMBER / RANK / DENSE_RANK
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- Partition
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Aggregate window functions
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

-- Offset functions
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

-- NTH_VALUE
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;

-- NTILE
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;

-- PERCENT_RANK / CUME_DIST
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;

-- Named window
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- Frame clauses
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- RANGE frame with INTERVAL
SELECT username, created_at, amount,
    SUM(amount) OVER (ORDER BY created_at RANGE BETWEEN
        INTERVAL 7 DAY PRECEDING AND CURRENT ROW) AS weekly_sum
FROM orders;

-- GROUPS frame mode
SELECT username, age,
    SUM(age) OVER (ORDER BY age GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS group_sum
FROM users;

-- FILTER clause with window functions
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) OVER () AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) OVER () AS senior_count
FROM users;

-- QUALIFY clause (DuckDB-specific: filter on window function results)
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
FROM users
QUALIFY rn <= 3;

-- QUALIFY without showing the window column
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) <= 3;

-- QUALIFY with complex conditions
SELECT username, city, age
FROM users
QUALIFY RANK() OVER (PARTITION BY city ORDER BY age) = 1
    OR age > (AVG(age) OVER (PARTITION BY city));

-- Window functions with EXCLUDE
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        EXCLUDE CURRENT ROW) AS neighbors_sum
FROM users;

-- LIST aggregate as window function (DuckDB-specific)
SELECT username, city,
    LIST(username) OVER (PARTITION BY city ORDER BY age) AS city_users_so_far
FROM users;

-- Note: QUALIFY is a powerful DuckDB/Snowflake feature that replaces subquery patterns
-- Note: All standard window functions are supported
-- Note: FILTER clause works with window aggregates
-- Note: EXCLUDE in frame clause: CURRENT ROW, GROUP, TIES, NO OTHERS
-- Note: Window functions are highly optimized in DuckDB's columnar engine
