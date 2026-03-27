-- Teradata: Window Functions
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

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

-- QUALIFY (Teradata-specific: filter on window function results)
-- Eliminates the need for a subquery wrapper
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users
QUALIFY city_rank = 1;

-- QUALIFY with inline expression
SELECT username, city, age
FROM users
QUALIFY RANK() OVER (PARTITION BY city ORDER BY age DESC) <= 3;

-- QUALIFY with aggregate window
SELECT username, age
FROM users
QUALIFY SUM(age) OVER (PARTITION BY city) > 100;

-- Frame clause
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_avg
FROM users;

-- Named window (WINDOW clause)
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- RESET WHEN (Teradata-specific: conditional window reset)
SELECT username, event_date, amount,
    SUM(amount) OVER (ORDER BY event_date
        RESET WHEN amount < 0) AS running_total
FROM events;

-- Note: Teradata pioneered QUALIFY (now adopted by Snowflake, DuckDB, etc.)
-- Note: RESET WHEN is unique to Teradata
-- Note: window functions are highly optimized for MPP execution
