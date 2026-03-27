-- Flink SQL: Conditional Functions (Flink 1.11+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

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

-- IFNULL (alias for COALESCE with 2 args, Flink 1.15+)
SELECT IFNULL(phone, 'N/A') FROM users;

-- IF (ternary expression, Flink 1.15+)
SELECT IF(age >= 18, 'adult', 'minor') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                             -- 3
SELECT LEAST(1, 3, 2);                                -- 1

-- Type casting
SELECT CAST('123' AS INT);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(TRUE AS INT);                             -- 1
SELECT CAST(123 AS STRING);

-- TRY_CAST (returns NULL on failure, Flink 1.15+)
SELECT TRY_CAST('abc' AS INT);                        -- NULL
SELECT TRY_CAST('invalid-date' AS DATE);              -- NULL

-- IS DISTINCT FROM (NULL-safe comparison)
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;  -- Same as IS NULL

-- NULL handling
SELECT * FROM users WHERE age IS NULL;
SELECT * FROM users WHERE age IS NOT NULL;

-- IS TRUE / IS FALSE / IS UNKNOWN
SELECT * FROM users WHERE active IS TRUE;
SELECT * FROM users WHERE active IS NOT TRUE;          -- FALSE or NULL
SELECT * FROM users WHERE active IS FALSE;
SELECT * FROM users WHERE active IS UNKNOWN;           -- Same as IS NULL for BOOLEAN

-- Boolean expressions in SELECT
SELECT username, age >= 18 AS is_adult FROM users;

-- IN expression
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai', 'Guangzhou');
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');

-- BETWEEN
SELECT * FROM users WHERE age BETWEEN 18 AND 65;
SELECT * FROM users WHERE age NOT BETWEEN 18 AND 65;

-- Conditional aggregation with CASE
SELECT
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior,
    SUM(IF(status = 1, amount, 0)) AS active_total
FROM users;

-- FILTER clause (Flink 1.14+)
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    SUM(amount) FILTER (WHERE status = 1) AS active_total
FROM users;

-- Conditional expressions in streaming
-- Common pattern: route events based on conditions
INSERT INTO error_events
SELECT * FROM all_events WHERE LOWER(level) = 'error';

INSERT INTO normal_events
SELECT * FROM all_events WHERE LOWER(level) != 'error';

-- Multiple output routing with STATEMENT SET
BEGIN STATEMENT SET;
INSERT INTO errors SELECT * FROM events WHERE severity = 'ERROR';
INSERT INTO warnings SELECT * FROM events WHERE severity = 'WARNING';
INSERT INTO info SELECT * FROM events WHERE severity = 'INFO';
END;

-- Note: CAST is the primary type conversion function
-- Note: TRY_CAST available from Flink 1.15+ for safe conversion
-- Note: IF function available from Flink 1.15+
-- Note: No :: cast operator (PostgreSQL-style)
-- Note: No DECODE function (Oracle-style)
-- Note: No NVL/NVL2 (use COALESCE instead)
-- Note: No TYPEOF function
-- Note: IS DISTINCT FROM is fully supported for NULL-safe comparison
-- Note: FILTER clause on aggregates available from Flink 1.14+
