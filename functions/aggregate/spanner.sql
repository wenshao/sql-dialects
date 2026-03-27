-- Google Cloud Spanner: Aggregate Functions (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Basic aggregates
SELECT COUNT(*) FROM Users;
SELECT COUNT(DISTINCT City) FROM Users;
SELECT SUM(Amount) FROM Orders;
SELECT AVG(Amount) FROM Orders;
SELECT MIN(Amount) FROM Orders;
SELECT MAX(Amount) FROM Orders;

-- GROUP BY
SELECT City, COUNT(*) AS Cnt, AVG(Age) AS AvgAge
FROM Users
GROUP BY City;

-- HAVING
SELECT City, COUNT(*) AS Cnt
FROM Users
GROUP BY City
HAVING COUNT(*) > 10;

-- GROUPING SETS (not directly supported; use UNION ALL)
SELECT City, NULL AS Status, COUNT(*) FROM Users GROUP BY City
UNION ALL
SELECT NULL, Status, COUNT(*) FROM Users GROUP BY Status
UNION ALL
SELECT NULL, NULL, COUNT(*) FROM Users;

-- ROLLUP
SELECT City, Status, COUNT(*)
FROM Users
GROUP BY ROLLUP (City, Status);

-- CUBE
SELECT City, Status, COUNT(*)
FROM Users
GROUP BY CUBE (City, Status);

-- GROUPING() function
SELECT City, GROUPING(City) AS IsTotal, COUNT(*)
FROM Users
GROUP BY ROLLUP (City);

-- String aggregation
SELECT STRING_AGG(Username, ', ' ORDER BY Username) FROM Users;
SELECT STRING_AGG(DISTINCT City, ', ') FROM Users;

-- Array aggregation
SELECT ARRAY_AGG(Username ORDER BY Username) FROM Users;
SELECT ARRAY_AGG(DISTINCT City) FROM Users;

-- ARRAY_CONCAT_AGG (concatenate arrays)
SELECT ARRAY_CONCAT_AGG(Tags) FROM Profiles;

-- Statistical functions
SELECT STDDEV(Amount) FROM Orders;                     -- sample std dev
SELECT STDDEV_POP(Amount) FROM Orders;                 -- population std dev
SELECT VARIANCE(Amount) FROM Orders;                   -- sample variance
SELECT VAR_POP(Amount) FROM Orders;                    -- population variance

-- Approximate aggregates (faster for large datasets)
SELECT APPROX_COUNT_DISTINCT(City) FROM Users;
SELECT APPROX_QUANTILES(Amount, 4) FROM Orders;        -- quartiles
SELECT APPROX_TOP_COUNT(City, 5) FROM Users;           -- top 5 cities
SELECT APPROX_TOP_SUM(City, Amount, 5) FROM Users;     -- top 5 by sum

-- COUNTIF (conditional count)
SELECT
    COUNT(*) AS total,
    COUNTIF(Age < 30) AS young,
    COUNTIF(Age >= 30) AS senior
FROM Users;

-- Logical aggregates
SELECT LOGICAL_AND(Active) FROM Users;                 -- all TRUE
SELECT LOGICAL_OR(Active) FROM Users;                  -- any TRUE

-- BIT aggregates
SELECT BIT_AND(Flags) FROM Settings;
SELECT BIT_OR(Flags) FROM Settings;
SELECT BIT_XOR(Flags) FROM Settings;

-- ANY_VALUE (arbitrary value from group)
SELECT City, ANY_VALUE(Username) FROM Users GROUP BY City;

-- Note: COUNTIF replaces PostgreSQL's COUNT(*) FILTER
-- Note: APPROX_* functions for approximate results (much faster)
-- Note: ARRAY_AGG and STRING_AGG supported
-- Note: No JSON_AGG or JSONB_AGG (use ARRAY_AGG + TO_JSON)
-- Note: LOGICAL_AND/LOGICAL_OR replace BOOL_AND/BOOL_OR
-- Note: FILTER clause not supported (use COUNTIF or CASE)
