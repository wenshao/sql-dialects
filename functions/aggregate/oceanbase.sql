-- OceanBase: Aggregate Functions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

-- Basic aggregates
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

-- WITH ROLLUP
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

-- GROUP_CONCAT
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

-- JSON aggregation
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- Statistical functions
SELECT STD(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;

-- ============================================================
-- Oracle Mode
-- ============================================================

-- Basic aggregates (same syntax)
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- ROLLUP (Oracle syntax, no WITH keyword)
SELECT city, COUNT(*) FROM users GROUP BY ROLLUP(city);

-- CUBE (Oracle mode, not available in MySQL mode)
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE(city, status);

-- GROUPING SETS (Oracle mode, not available in MySQL mode)
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS (
    (city),
    (status),
    (city, status),
    ()
);

-- GROUPING function (use with ROLLUP/CUBE/GROUPING SETS)
SELECT city, COUNT(*), GROUPING(city) AS is_total
FROM users
GROUP BY ROLLUP(city);

-- LISTAGG (Oracle mode, equivalent to GROUP_CONCAT)
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
FROM users
GROUP BY city;

-- KEEP (DENSE_RANK FIRST/LAST) (Oracle mode)
SELECT city,
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS earliest_user_age,
    MAX(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS latest_user_age
FROM users
GROUP BY city;

-- MEDIAN (Oracle mode)
SELECT city, MEDIAN(age) FROM users GROUP BY city;

-- PERCENTILE_CONT / PERCENTILE_DISC (Oracle mode)
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) AS median_disc
FROM users
GROUP BY city;

-- STATS_MODE (Oracle mode, return most frequent value)
-- Limited support in OceanBase

-- Parallel aggregation hint
SELECT /*+ PARALLEL(4) */ city, SUM(amount)
FROM orders
GROUP BY city;

-- Limitations:
-- MySQL mode: same as MySQL (no CUBE, GROUPING SETS)
-- Oracle mode: CUBE, GROUPING SETS, ROLLUP all supported
-- Oracle mode: LISTAGG, KEEP, MEDIAN, PERCENTILE functions
-- Oracle mode: GROUPING function for rollup/cube queries
-- Aggregate parallelism depends on cluster resources
