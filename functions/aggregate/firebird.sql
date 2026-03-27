-- Firebird: Aggregate Functions
--
-- 参考资料:
--   [1] Firebird SQL Reference
--       https://firebirdsql.org/en/reference-manuals/
--   [2] Firebird Release Notes
--       https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html

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

-- String aggregation (LIST function, Firebird-specific)
SELECT LIST(username, ', ') FROM users;
SELECT LIST(DISTINCT city, '; ') FROM users;
SELECT city, LIST(username, ', ') FROM users GROUP BY city;

-- Note: LIST() does not support ORDER BY inside the function
-- For ordered aggregation, use subquery
SELECT LIST(username, ', ')
FROM (SELECT username FROM users ORDER BY username);

-- GROUPING SETS (not supported in Firebird)
-- Workaround: UNION ALL
SELECT city, NULL AS status, COUNT(*) FROM users GROUP BY city
UNION ALL
SELECT NULL, status, COUNT(*) FROM users GROUP BY status
UNION ALL
SELECT NULL, NULL, COUNT(*) FROM users;

-- Statistical functions (3.0+)
SELECT STDDEV_SAMP(amount) FROM orders;       -- sample standard deviation
SELECT STDDEV_POP(amount) FROM orders;        -- population standard deviation
SELECT VAR_SAMP(amount) FROM orders;          -- sample variance
SELECT VAR_POP(amount) FROM orders;           -- population variance
SELECT CORR(x, y) FROM data;                 -- correlation (3.0+)
SELECT COVAR_SAMP(x, y) FROM data;           -- sample covariance (3.0+)
SELECT COVAR_POP(x, y) FROM data;            -- population covariance (3.0+)
SELECT REGR_SLOPE(y, x) FROM data;           -- regression slope (3.0+)
SELECT REGR_INTERCEPT(y, x) FROM data;       -- regression intercept (3.0+)
SELECT REGR_R2(y, x) FROM data;              -- R-squared (3.0+)
SELECT REGR_COUNT(y, x) FROM data;           -- non-null pair count (3.0+)

-- Conditional aggregation (CASE WHEN)
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior
FROM users;

-- 4.0+: FILTER clause for conditional aggregation
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

-- Boolean aggregates (3.0+)
SELECT EVERY(active) FROM users;               -- all TRUE (SQL standard)
SELECT ANY_VALUE(city) FROM users;             -- return any value (4.0+)

-- Note: LIST() is Firebird's string aggregation (unique name)
-- Note: no GROUPING SETS / ROLLUP / CUBE
-- Note: statistical functions added in 3.0
-- Note: FILTER clause added in 4.0
-- Note: no PERCENTILE_CONT / PERCENTILE_DISC
