-- MariaDB: Conditional Functions
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

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

-- CAST / CONVERT (same as MySQL, but without some MySQL 8.0 additions)
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);

-- CAST to INET4 / INET6 (10.10+, MariaDB-specific)
SELECT CAST('192.168.1.1' AS INET4);
SELECT CAST('::ffff:192.168.1.1' AS INET6);

-- CAST to UUID (10.7+, MariaDB-specific)
SELECT CAST('550e8400-e29b-41d4-a716-446655440000' AS UUID);

-- ELT / FIELD (same as MySQL)
SELECT ELT(2, 'a', 'b', 'c');
SELECT FIELD('b', 'a', 'b', 'c');

-- GREATEST / LEAST (same as MySQL)
SELECT GREATEST(1, 3, 2);
SELECT LEAST(1, 3, 2);

-- ISNULL (same as MySQL)
SELECT ISNULL(phone) FROM users;

-- DECODE: MariaDB supports Oracle-style DECODE (10.3+, with sql_mode=ORACLE)
-- In ORACLE sql_mode:
-- SET sql_mode = 'ORACLE';
-- SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;
-- In default sql_mode, DECODE is for base-64 decoding

-- NVL / NVL2: available in ORACLE sql_mode (10.3+)
-- SET sql_mode = 'ORACLE';
-- SELECT NVL(phone, 'N/A') FROM users;
-- SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- ROWNUM: available in ORACLE sql_mode (10.6+)
-- SET sql_mode = 'ORACLE';
-- SELECT * FROM users WHERE ROWNUM <= 10;

-- NATURAL_SORT_KEY in conditional context (10.7.1+)
SELECT username,
    CASE
        WHEN NATURAL_SORT_KEY(username) < NATURAL_SORT_KEY('user100')
        THEN 'before'
        ELSE 'after'
    END AS position
FROM users;

-- Differences from MySQL 8.0:
-- CAST to INET4, INET6 (MariaDB-specific native types)
-- CAST to UUID (MariaDB-specific native type)
-- ORACLE sql_mode enables DECODE, NVL, NVL2, ROWNUM
-- No CAST to ARRAY (MySQL 8.0.17+)
-- Same core conditional functions (CASE, IF, IFNULL, COALESCE, NULLIF)
-- All standard conditional behavior identical to MySQL
