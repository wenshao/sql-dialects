-- OceanBase: Window Functions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL 8.0)
-- ============================================================

-- ROW_NUMBER / RANK / DENSE_RANK
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- PARTITION BY
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Aggregate window functions
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER (PARTITION BY city) AS city_avg
FROM users;

-- LAG / LEAD
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age
FROM users;

-- Named window
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk
FROM users
WINDOW w AS (ORDER BY age);

-- Frame clause
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- ============================================================
-- Oracle Mode (richer window function support)
-- ============================================================

-- ROW_NUMBER / RANK / DENSE_RANK (same syntax)
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- PARTITION BY (same syntax)
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- LISTAGG (Oracle mode, string aggregation with window)
SELECT username, city,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
        OVER (PARTITION BY city) AS city_users
FROM users;

-- RATIO_TO_REPORT (Oracle mode)
SELECT username, amount,
    RATIO_TO_REPORT(amount) OVER () AS pct_of_total
FROM orders;

-- FIRST / LAST (Oracle mode, aggregate KEEP)
SELECT city,
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS earliest_user_age,
    MAX(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS latest_user_age
FROM users
GROUP BY city;

-- RANGE frame with interval (Oracle mode)
SELECT username, created_at, amount,
    SUM(amount) OVER (ORDER BY created_at
        RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW) AS week_total
FROM orders;

-- Parallel execution with hints
SELECT /*+ PARALLEL(4) */ username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Limitations:
-- MySQL mode: standard MySQL 8.0 window functions
-- Oracle mode: additional Oracle-specific analytic functions
-- LISTAGG, RATIO_TO_REPORT, KEEP (DENSE_RANK FIRST/LAST) are Oracle-mode only
-- Named windows supported in both modes
