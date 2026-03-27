-- CockroachDB: Aggregate Functions (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- Basic aggregates (same as PostgreSQL)
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

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

-- JSON aggregation
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;
SELECT JSONB_OBJECT_AGG(username, age) FROM users;

-- Array aggregation
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;

-- Statistical functions
SELECT STDDEV(amount) FROM orders;                     -- sample std dev
SELECT STDDEV_POP(amount) FROM orders;                 -- population std dev
SELECT VARIANCE(amount) FROM orders;                   -- sample variance
SELECT VAR_POP(amount) FROM orders;                    -- population variance
SELECT CORR(x, y) FROM data;                          -- correlation
SELECT COVAR_SAMP(x, y) FROM data;                    -- sample covariance
SELECT REGR_SLOPE(y, x) FROM data;                    -- linear regression slope

-- FILTER clause (conditional aggregation)
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

-- Boolean aggregates
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
SELECT EVERY(active) FROM users;                       -- same as BOOL_AND

-- BIT aggregates
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;

-- XOR aggregate (CockroachDB-specific)
SELECT XOR_AGG(flags) FROM settings;

-- Note: All PostgreSQL aggregate functions supported
-- Note: FILTER clause supported for conditional aggregation
-- Note: GROUPING SETS, ROLLUP, CUBE all supported
-- Note: Aggregations work across distributed nodes
-- Note: XOR_AGG is CockroachDB-specific
