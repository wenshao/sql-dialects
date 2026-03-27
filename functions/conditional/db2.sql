-- IBM Db2: Conditional Functions
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- CASE WHEN
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
SELECT NULLIF(age, 0) FROM users;

-- NVL (Db2 11.1+, Oracle-compatible)
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2 (Db2 11.1+, Oracle-compatible)
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- GREATEST / LEAST (Db2 11.1+)
SELECT GREATEST(1, 3, 2) FROM SYSIBM.SYSDUMMY1;            -- 3
SELECT LEAST(1, 3, 2) FROM SYSIBM.SYSDUMMY1;               -- 1

-- DECODE (Db2 11.1+, Oracle-compatible)
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

-- Type casting
SELECT CAST('123' AS INTEGER) FROM SYSIBM.SYSDUMMY1;
SELECT CAST('2024-01-15' AS DATE) FROM SYSIBM.SYSDUMMY1;
SELECT INTEGER('123') FROM SYSIBM.SYSDUMMY1;                -- Db2-specific cast function
SELECT VARCHAR(123) FROM SYSIBM.SYSDUMMY1;
SELECT DATE('2024-01-15') FROM SYSIBM.SYSDUMMY1;

-- VALUE (Db2 synonym for COALESCE)
SELECT VALUE(phone, email, 'unknown') FROM users;

-- IFNULL (Db2-specific, synonym for COALESCE with 2 args)
SELECT IFNULL(phone, 'N/A') FROM users;

-- Boolean expressions (Db2 11.1+)
SELECT username, (age >= 18) AS is_adult FROM users;

-- IS [NOT] NULL
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- BETWEEN
SELECT * FROM users WHERE age BETWEEN 18 AND 65;

-- IN
SELECT * FROM users WHERE status IN (1, 2, 3);

-- Nested CASE
SELECT username,
    CASE
        WHEN age IS NULL THEN 'unknown age'
        WHEN age < 18 THEN
            CASE status WHEN 1 THEN 'active minor' ELSE 'inactive minor' END
        ELSE 'adult'
    END AS description
FROM users;

-- LNNVL (Db2 11.1+, evaluates condition, returns TRUE if FALSE or NULL)
-- Useful for NOT conditions with NULLs
SELECT * FROM users WHERE LNNVL(age > 18);  -- includes NULL ages

-- Note: VALUE / IFNULL are Db2-specific synonyms for COALESCE
-- Note: DECODE, NVL, NVL2 added in Db2 11.1 for Oracle compatibility
-- Note: type-name functions (INTEGER(), VARCHAR()) are Db2-specific casting
