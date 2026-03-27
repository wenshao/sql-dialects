-- MariaDB: Window Functions (10.2+)
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
-- MariaDB added window functions in 10.2, earlier than MySQL 8.0.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- All standard window functions supported since 10.2:
-- ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD,
-- FIRST_VALUE, LAST_VALUE, NTH_VALUE, PERCENT_RANK, CUME_DIST

-- ROW_NUMBER / RANK / DENSE_RANK (same as MySQL 8.0)
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

-- PARTITION BY (same as MySQL 8.0)
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

-- Aggregate window functions (same as MySQL 8.0)
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER (PARTITION BY city) AS city_avg,
    COUNT(*)   OVER () AS total_count
FROM users;

-- LAG / LEAD (same as MySQL 8.0)
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age
FROM users;

-- Named window (same as MySQL 8.0)
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

-- Frame clause (same as MySQL 8.0)
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

-- PERCENTILE_CONT / PERCENTILE_DISC (10.3.3+)
-- MariaDB supports these as window functions (not available in MySQL)
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS median_age_disc
FROM users;

-- MEDIAN (10.3.3+): shorthand for PERCENTILE_CONT(0.5)
-- Not available in MySQL
SELECT city,
    MEDIAN(age) OVER (PARTITION BY city) AS median_age
FROM users;

-- Aggregate functions as window functions
-- MariaDB allows GROUP_CONCAT as a window function (10.2+)
-- Not supported in MySQL window context
-- Note: behavior may vary by version

-- EXCLUDE clause in frame specification (10.2+)
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        EXCLUDE CURRENT ROW) AS neighbor_sum
FROM users;
-- EXCLUDE options: CURRENT ROW, GROUP, TIES, NO OTHERS

-- Differences from MySQL 8.0:
-- Window functions available since 10.2 (earlier than MySQL 8.0)
-- PERCENTILE_CONT/PERCENTILE_DISC supported (not in MySQL)
-- MEDIAN function supported (not in MySQL)
-- EXCLUDE clause in frame specification supported (not in MySQL)
-- Generally similar performance characteristics
-- optimizer_switch controls window function execution strategy
