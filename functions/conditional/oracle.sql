-- Oracle: 条件函数
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CASE Expressions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CASE-Expressions.html
--   [2] Oracle SQL Language Reference - Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html

-- CASE WHEN
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- 简单 CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- DECODE（Oracle 特有，简单 CASE 的简写）
SELECT username,
    DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') AS status_name
FROM users;

-- NVL（两参数 NULL 替换，Oracle 特有）
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2（三参数：非 NULL 时返回第二个，NULL 时返回第三个）
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- COALESCE（SQL 标准）
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2) FROM dual;                     -- 3
SELECT LEAST(1, 3, 2) FROM dual;                         -- 1
-- 注意：Oracle 的 GREATEST/LEAST 在参数包含 NULL 时返回 NULL

-- LNNVL（返回条件为 FALSE 或 NULL 的行，常用于 WHERE）
SELECT * FROM users WHERE LNNVL(age > 18);              -- age <= 18 或 age IS NULL

-- 类型转换
SELECT CAST('123' AS NUMBER) FROM dual;
SELECT TO_NUMBER('123') FROM dual;
SELECT TO_CHAR(123) FROM dual;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM dual;

-- DUMP（显示值的内部表示）
SELECT DUMP('hello') FROM dual;

-- ORA_HASH（哈希值）
SELECT ORA_HASH(username) FROM users;
