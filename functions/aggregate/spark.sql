-- Spark SQL: Aggregate Functions (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

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

-- GROUPING_ID() (returns bitmask of grouping columns)
SELECT city, status, GROUPING_ID(city, status), COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- Collection aggregates
SELECT COLLECT_LIST(username) FROM users;              -- List with duplicates
SELECT COLLECT_SET(city) FROM users;                   -- Set without duplicates
SELECT SORT_ARRAY(COLLECT_LIST(username)) FROM users;  -- Sorted list

-- String aggregation (via COLLECT_LIST + CONCAT_WS)
SELECT CONCAT_WS(', ', COLLECT_LIST(username)) FROM users;
-- Or with sorting:
SELECT CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(username))) FROM users;

-- Map aggregation
SELECT MAP_FROM_ENTRIES(COLLECT_LIST(STRUCT(username, age))) FROM users;

-- Approximate aggregates
SELECT APPROX_COUNT_DISTINCT(city) FROM users;         -- HyperLogLog
SELECT PERCENTILE_APPROX(age, 0.5) FROM users;        -- Approximate median
SELECT PERCENTILE_APPROX(age, ARRAY(0.25, 0.5, 0.75)) FROM users;  -- Multiple

-- Exact percentiles
SELECT PERCENTILE(age, 0.5) FROM users;                -- Exact median
SELECT PERCENTILE(age, ARRAY(0.25, 0.5, 0.75)) FROM users;

-- Statistical functions
SELECT STDDEV(amount) FROM orders;                     -- Sample standard deviation
SELECT STDDEV_POP(amount) FROM orders;                 -- Population standard deviation
SELECT STDDEV_SAMP(amount) FROM orders;                -- Sample (alias)
SELECT VARIANCE(amount) FROM orders;                   -- Sample variance
SELECT VAR_POP(amount) FROM orders;                    -- Population variance
SELECT VAR_SAMP(amount) FROM orders;                   -- Sample (alias)
SELECT CORR(x, y) FROM data;                          -- Correlation
SELECT COVAR_SAMP(x, y) FROM data;                    -- Sample covariance
SELECT COVAR_POP(x, y) FROM data;                     -- Population covariance
SELECT REGR_SLOPE(y, x) FROM data;                    -- (Spark 3.3+)
SELECT REGR_INTERCEPT(y, x) FROM data;                -- (Spark 3.3+)
SELECT REGR_R2(y, x) FROM data;                       -- (Spark 3.3+)
SELECT KURTOSIS(age) FROM users;                       -- Kurtosis
SELECT SKEWNESS(age) FROM users;                       -- Skewness

-- Conditional aggregation (no FILTER clause, use CASE or IF)
SELECT
    COUNT(*) AS total,
    COUNT(IF(age < 30, 1, NULL)) AS young,
    SUM(CASE WHEN status = 'completed' THEN amount ELSE 0 END) AS completed_total,
    COUNT_IF(age >= 30) AS senior                      -- Spark 3.0+
FROM users;

-- FILTER clause (Spark 3.2+)
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young
FROM users;

-- Boolean aggregates
SELECT BOOL_AND(active) FROM users;                    -- Spark 3.0+
SELECT BOOL_OR(active) FROM users;                     -- Spark 3.0+
SELECT EVERY(active) FROM users;                       -- Alias for BOOL_AND
SELECT SOME(active) FROM users;                        -- Alias for BOOL_OR
SELECT ANY(active) FROM users;                         -- Alias for BOOL_OR

-- Bit aggregates
SELECT BIT_AND(flags) FROM settings;                   -- Spark 3.0+
SELECT BIT_OR(flags) FROM settings;                    -- Spark 3.0+
SELECT BIT_XOR(flags) FROM settings;                   -- Spark 3.0+

-- FIRST / LAST (non-deterministic without ORDER BY in GROUP BY)
SELECT city, FIRST(username) FROM users GROUP BY city;
SELECT city, LAST(username) FROM users GROUP BY city;
SELECT city, FIRST(username, true) FROM users GROUP BY city; -- Ignore nulls

-- MIN_BY / MAX_BY (Spark 3.3+)
SELECT MIN_BY(username, age) FROM users;               -- Username of youngest
SELECT MAX_BY(username, age) FROM users;               -- Username of oldest

-- Note: No GROUP BY ALL (must list all non-aggregate columns)
-- Note: COLLECT_LIST/COLLECT_SET return ArrayType (Spark-specific)
-- Note: No HISTOGRAM; use GROUP BY + COUNT for frequency distribution
-- Note: FILTER clause added in Spark 3.2+; before that use IF/CASE
-- Note: MIN_BY/MAX_BY added in Spark 3.3+
-- Note: FIRST/LAST are non-deterministic within groups
-- Note: KURTOSIS and SKEWNESS are built-in (not common in other databases)
