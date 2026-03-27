-- TiDB: Conditional Functions
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- CASE WHEN (same as MySQL)
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- Simple CASE (same as MySQL)
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- IF (same as MySQL)
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- IFNULL (same as MySQL)
SELECT IFNULL(phone, 'N/A') FROM users;

-- COALESCE (same as MySQL)
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF (same as MySQL)
SELECT NULLIF(age, 0) FROM users;

-- CAST / CONVERT (same as MySQL)
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);

-- ELT / FIELD (same as MySQL)
SELECT ELT(2, 'a', 'b', 'c');
SELECT FIELD('b', 'a', 'b', 'c');

-- GREATEST / LEAST (same as MySQL)
SELECT GREATEST(1, 3, 2);
SELECT LEAST(1, 3, 2);

-- ISNULL (same as MySQL)
SELECT ISNULL(phone) FROM users;

-- TiDB-specific: conditional with TiFlash
-- When using TiFlash replicas, conditional expressions are pushed down
SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */ username,
    CASE WHEN age >= 18 THEN 'adult' ELSE 'minor' END AS category
FROM users;

-- TiDB-specific: CAST to JSON types
SELECT CAST('{"a":1}' AS JSON);
SELECT CAST(123 AS JSON);  -- not available in MySQL 5.7, works in TiDB

-- Limitations:
-- All MySQL conditional functions work identically
-- No differences in CASE, IF, IFNULL, COALESCE, NULLIF behavior
-- Type casting follows MySQL rules
-- Some edge cases in CAST behavior may differ slightly from MySQL
