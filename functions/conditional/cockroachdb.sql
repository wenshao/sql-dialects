-- CockroachDB: Conditional Functions (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- CASE WHEN (same as PostgreSQL)
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

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;              -- returns NULL if age = 0

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                      -- 3
SELECT LEAST(1, 3, 2);                         -- 1

-- Type casting (PostgreSQL syntax)
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                          -- :: syntax
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

-- IF (CockroachDB-specific function, not in PostgreSQL)
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
-- Same as: CASE WHEN age >= 18 THEN 'adult' ELSE 'minor' END

-- IFNULL (CockroachDB-specific, same as COALESCE with 2 args)
SELECT IFNULL(phone, 'N/A') FROM users;
-- Same as: COALESCE(phone, 'N/A')

-- NVL (CockroachDB-specific alias for IFNULL)
SELECT NVL(phone, 'N/A') FROM users;

-- Boolean expression as value (same as PostgreSQL)
SELECT username, (age >= 18) AS is_adult FROM users;

-- IS DISTINCT FROM (NULL-safe comparison)
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

-- num_nulls / num_nonnulls
SELECT num_nulls(phone, email, city) FROM users;
SELECT num_nonnulls(phone, email, city) FROM users;

-- IFERROR (CockroachDB-specific)
-- SELECT IFERROR(1/0, -1);  -- returns -1 instead of error

-- ISERROR (CockroachDB-specific)
-- SELECT ISERROR(1/0);  -- returns TRUE

-- Note: IF(), IFNULL(), NVL() are CockroachDB-specific
-- Note: :: casting syntax supported (PostgreSQL-compatible)
-- Note: IS DISTINCT FROM for NULL-safe comparisons
-- Note: GREATEST/LEAST return NULL if any argument is NULL
-- Note: No TRY_CAST (use conditional logic)
