-- DuckDB: Conditional Functions (v0.8+)
--
-- 参考资料:
--   [1] DuckDB - SQL Reference
--       https://duckdb.org/docs/sql/introduction
--   [2] DuckDB - Functions
--       https://duckdb.org/docs/sql/functions/overview
--   [3] DuckDB - Data Types
--       https://duckdb.org/docs/sql/data_types/overview

-- CASE WHEN (searched)
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- Simple CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE (first non-NULL)
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF (returns NULL if equal)
SELECT NULLIF(age, 0) FROM users;

-- IFNULL (DuckDB-specific, alias for COALESCE with 2 args)
SELECT IFNULL(phone, 'N/A') FROM users;

-- IF (DuckDB-specific, ternary expression)
SELECT IF(age >= 18, 'adult', 'minor') FROM users;

-- IIF (alias for IF)
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                             -- 3
SELECT LEAST(1, 3, 2);                                -- 1
SELECT GREATEST(a, b, c) FROM scores;
SELECT LEAST(price1, price2, price3) FROM products;

-- Type casting
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                -- PostgreSQL-style cast
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(TRUE AS INTEGER);                         -- 1

-- TRY_CAST (returns NULL on failure, DuckDB-specific)
SELECT TRY_CAST('abc' AS INTEGER);                    -- NULL (no error)
SELECT TRY_CAST('2024-13-45' AS DATE);                -- NULL
SELECT TRY_CAST('3.14' AS DOUBLE);                    -- 3.14

-- TYPEOF (returns type name as string)
SELECT TYPEOF(42);                                     -- 'INTEGER'
SELECT TYPEOF('hello');                                -- 'VARCHAR'
SELECT TYPEOF(NOW());                                  -- 'TIMESTAMP WITH TIME ZONE'

-- IS DISTINCT FROM (NULL-safe comparison)
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;  -- Same as IS NULL

-- NULL handling
SELECT * FROM users WHERE age IS NULL;
SELECT * FROM users WHERE age IS NOT NULL;

-- Boolean expressions
SELECT username, (age >= 18) AS is_adult FROM users;   -- Boolean result
SELECT * FROM users WHERE active IS TRUE;
SELECT * FROM users WHERE active IS NOT TRUE;          -- FALSE or NULL
SELECT * FROM users WHERE active IS FALSE;
SELECT * FROM users WHERE active IS UNKNOWN;           -- Same as IS NULL for BOOLEAN

-- Conditional aggregation
SELECT
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior,
    SUM(IF(status = 1, amount, 0)) AS active_total
FROM users;

-- COLUMNS expression with conditional (DuckDB-specific)
SELECT COLUMNS('amount_.*') FROM orders;               -- Select columns by regex
SELECT MIN(COLUMNS(*)) FROM orders;                    -- MIN of each column

-- UNION type check (DuckDB-specific)
SELECT UNION_TAG(value) FROM complex_data;             -- Returns active tag name

-- Note: TRY_CAST is a key DuckDB feature for safe type conversion
-- Note: IF/IIF provide concise ternary expressions
-- Note: TYPEOF returns the type name as a string
-- Note: IS DISTINCT FROM handles NULL comparison correctly
-- Note: COLUMNS(*) expression is unique to DuckDB for columnar operations
-- Note: No DECODE function (Oracle-style); use CASE instead
