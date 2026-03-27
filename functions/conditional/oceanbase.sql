-- OceanBase: Conditional Functions
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode (same as MySQL)
-- ============================================================

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
        ELSE 'unknown'
    END AS status_name
FROM users;

-- IF
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- IFNULL
SELECT IFNULL(phone, 'N/A') FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- CAST / CONVERT
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);

-- ELT / FIELD
SELECT ELT(2, 'a', 'b', 'c');
SELECT FIELD('b', 'a', 'b', 'c');

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);
SELECT LEAST(1, 3, 2);

-- ============================================================
-- Oracle Mode
-- ============================================================

-- CASE WHEN (same syntax)
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- DECODE (Oracle-specific, similar to CASE)
SELECT username,
    DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') AS status_name
FROM users;
-- DECODE(expr, search1, result1, search2, result2, ..., default)

-- NVL (Oracle-specific, similar to IFNULL)
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2 (Oracle-specific, 3-argument NULL check)
-- NVL2(expr, value_if_not_null, value_if_null)
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- COALESCE (same as SQL standard)
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF (same as SQL standard)
SELECT NULLIF(age, 0) FROM users;

-- GREATEST / LEAST (same syntax but NULL handling differs!)
-- Oracle: if any argument is NULL, result is NULL
-- MySQL: NULL is treated as less than non-NULL
SELECT GREATEST(1, 3, NULL) FROM DUAL;    -- NULL in Oracle mode
SELECT LEAST(1, 3, NULL) FROM DUAL;       -- NULL in Oracle mode

-- CAST (Oracle syntax)
SELECT CAST('123' AS NUMBER) FROM DUAL;
SELECT CAST('2024-01-15' AS DATE) FROM DUAL;
SELECT CAST(123 AS VARCHAR2(10)) FROM DUAL;

-- TO_NUMBER / TO_CHAR / TO_DATE (Oracle type conversion)
SELECT TO_NUMBER('123.45') FROM DUAL;
SELECT TO_CHAR(123, '9999.99') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;

-- LNNVL (Oracle-specific, returns TRUE for NULL or FALSE conditions)
SELECT * FROM users WHERE LNNVL(age > 65);  -- returns rows where age <= 65 OR age IS NULL

-- NANVL (Oracle-specific, for floating-point NaN handling)
SELECT NANVL(val, 0) FROM measurements;

-- SIGN function
SELECT SIGN(-5) FROM DUAL;   -- -1
SELECT SIGN(0) FROM DUAL;    -- 0
SELECT SIGN(5) FROM DUAL;    -- 1

-- Limitations:
-- MySQL mode: same as MySQL conditional functions
-- Oracle mode: DECODE, NVL, NVL2 instead of IF, IFNULL
-- Oracle mode: different NULL handling in GREATEST/LEAST
-- Oracle mode: TO_NUMBER/TO_CHAR/TO_DATE for type conversion
-- Oracle mode: no IF() function (use CASE or DECODE)
-- Oracle mode: no ELT/FIELD functions
