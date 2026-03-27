-- Spark SQL: Conditional Functions (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

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

-- IFNULL (Spark 2.4+, alias for COALESCE with 2 args)
SELECT IFNULL(phone, 'N/A') FROM users;

-- NVL (alias for IFNULL, Hive-compatible)
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2 (Spark 2.4+: if not null then X, else Y)
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- IF (ternary expression)
SELECT IF(age >= 18, 'adult', 'minor') FROM users;

-- IIF (Spark 3.2+, alias for IF)
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                             -- 3
SELECT LEAST(1, 3, 2);                                -- 1
-- Note: Returns NULL if any argument is NULL (Spark behavior)

-- Type casting
SELECT CAST('123' AS INT);
SELECT INT('123');                                     -- Function-style cast
SELECT DOUBLE('3.14');
SELECT STRING(123);
SELECT BOOLEAN('true');
SELECT CAST('2024-01-15' AS DATE);

-- TRY_CAST (returns NULL on failure, Spark 3.4+)
SELECT TRY_CAST('abc' AS INT);                        -- NULL
SELECT TRY_CAST('2024-13-45' AS DATE);                -- NULL

-- TYPEOF (Spark 3.0+)
SELECT TYPEOF(42);                                     -- 'int'
SELECT TYPEOF('hello');                                -- 'string'

-- IS DISTINCT FROM (Spark 3.2+)
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;

-- NULL handling
SELECT * FROM users WHERE age IS NULL;
SELECT * FROM users WHERE age IS NOT NULL;
SELECT * FROM users WHERE ISNULL(age);                 -- Function form
SELECT * FROM users WHERE ISNOTNULL(age);              -- Function form

-- NANVL (return second argument if first is NaN)
SELECT NANVL(DOUBLE('NaN'), 0.0);                     -- 0.0

-- DECODE (Oracle-compatible conditional expression)
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

-- Conditional aggregation
SELECT
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(IF(status = 1, amount, 0)) AS active_total,
    COUNT_IF(age >= 30) AS senior_count                -- Spark 3.0+
FROM users;

-- FILTER clause (Spark 3.2+)
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young
FROM users;

-- Boolean handling
SELECT * FROM users WHERE active = TRUE;
SELECT * FROM users WHERE active = FALSE;
SELECT * FROM users WHERE NOT active;

-- ASSERT_TRUE (Spark 3.1+, throws error if condition is false)
-- SELECT ASSERT_TRUE(age >= 0, 'Age must be non-negative') FROM users;

-- Stack function (pivots columns to rows)
SELECT stack(2, 'name', username, 'email', email) AS (field, value)
FROM users;

-- Note: IF() is the standard ternary function in Spark
-- Note: NVL/NVL2 are Hive-compatible alternatives to COALESCE
-- Note: DECODE provides Oracle-style conditional logic
-- Note: TRY_CAST added in Spark 3.4+ for safe conversion
-- Note: GREATEST/LEAST return NULL if any argument is NULL (unlike some databases)
-- Note: No :: cast operator (use CAST or function-style)
-- Note: TYPEOF returns lowercase type names ('int', 'string', etc.)
