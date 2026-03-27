-- Teradata: Aggregate Functions
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

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

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() function
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- Statistical functions
SELECT STDDEV_SAMP(amount) FROM orders;        -- sample standard deviation
SELECT STDDEV_POP(amount) FROM orders;         -- population standard deviation
SELECT VAR_SAMP(amount) FROM orders;           -- sample variance
SELECT VAR_POP(amount) FROM orders;            -- population variance
SELECT CORR(x, y) FROM data;                  -- correlation coefficient
SELECT COVAR_SAMP(x, y) FROM data;            -- sample covariance
SELECT COVAR_POP(x, y) FROM data;             -- population covariance
SELECT REGR_SLOPE(y, x) FROM data;            -- linear regression slope
SELECT REGR_INTERCEPT(y, x) FROM data;        -- linear regression intercept
SELECT REGR_R2(y, x) FROM data;               -- coefficient of determination
SELECT REGR_COUNT(y, x) FROM data;            -- non-null pair count

-- Teradata-specific aggregates
-- KURTOSIS (excess kurtosis)
SELECT KURTOSIS(age) FROM users;
-- SKEW (skewness)
SELECT SKEW(age) FROM users;

-- Percentile
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;  -- median
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) FROM users;

-- SAMPLE with aggregation
SELECT city, COUNT(*), AVG(age) FROM users SAMPLE 1000 GROUP BY city;

-- String aggregation (no direct STRING_AGG)
-- Use XML approach or ordered analytics

-- Top-N per group using QUALIFY
SELECT city, username, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) <= 3;

-- Note: Teradata supports extensive OLAP and statistical functions
-- Note: KURTOSIS and SKEW are Teradata-specific
-- Note: SAMPLE can be combined with aggregation
-- Note: no FILTER clause for conditional aggregation; use CASE WHEN
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior
FROM users;
