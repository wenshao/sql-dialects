-- SAP HANA: Conditional Functions
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

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

-- IFNULL (SAP HANA specific, two arguments)
SELECT IFNULL(phone, 'N/A') FROM users;

-- NVL (Oracle-compatible)
SELECT NVL(phone, 'N/A') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2) FROM DUMMY;                       -- 3
SELECT LEAST(1, 3, 2) FROM DUMMY;                           -- 1

-- Type casting
SELECT CAST('123' AS INTEGER) FROM DUMMY;
SELECT CAST('2024-01-15' AS DATE) FROM DUMMY;
SELECT TO_INTEGER('123') FROM DUMMY;
SELECT TO_VARCHAR(123) FROM DUMMY;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUMMY;
SELECT TO_DECIMAL('123.45', 10, 2) FROM DUMMY;
SELECT TO_BIGINT('123456789') FROM DUMMY;

-- DECODE (Oracle-compatible)
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

-- IF (SQLScript only, not in SQL)
-- In SQL, use CASE WHEN

-- MAP (SAP HANA-specific: multi-value mapping)
SELECT MAP(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;
-- Same as DECODE

-- Boolean expressions
SELECT username, (age >= 18) AS is_adult FROM users;

-- IS [NOT] NULL
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- BETWEEN
SELECT * FROM users WHERE age BETWEEN 18 AND 65;

-- IN
SELECT * FROM users WHERE status IN (1, 2, 3);

-- SIGN (returns -1, 0, or 1)
SELECT SIGN(-5) FROM DUMMY;                                 -- -1
SELECT SIGN(0) FROM DUMMY;                                  -- 0
SELECT SIGN(5) FROM DUMMY;                                  -- 1

-- ABS
SELECT ABS(-5) FROM DUMMY;                                  -- 5

-- Nested CASE
SELECT username,
    CASE
        WHEN age IS NULL THEN 'unknown age'
        WHEN age < 18 THEN
            CASE status WHEN 1 THEN 'active minor' ELSE 'inactive minor' END
        ELSE 'adult'
    END AS description
FROM users;

-- Note: IFNULL is preferred over COALESCE for two-argument case (SAP convention)
-- Note: MAP is SAP HANA's synonym for DECODE
-- Note: TO_* functions are preferred over CAST for type conversion
-- Note: DUMMY is the single-row system table
