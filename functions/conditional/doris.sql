-- Apache Doris: 条件函数
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- CASE WHEN（SQL 标准）
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
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- IF（MySQL 兼容）
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- IFNULL（两参数，NULL 替换）
SELECT IFNULL(phone, 'N/A') FROM users;

-- COALESCE（SQL 标准，返回第一个非 NULL 值）
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF（两值相等返回 NULL）
SELECT NULLIF(age, 0) FROM users;

-- NVL（等同于 IFNULL，Oracle 兼容）
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2（Oracle 兼容）
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
-- phone 非 NULL 返回第二个参数，NULL 返回第三个

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(123 AS VARCHAR);

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- NULL 判断
SELECT username FROM users WHERE age IS NULL;
SELECT username FROM users WHERE age IS NOT NULL;

-- 布尔函数
SELECT username FROM users WHERE IF(age > 18, TRUE, FALSE);

-- 注意：Doris 兼容 MySQL 条件函数
-- 注意：额外支持 NVL, NVL2（Oracle 兼容）
-- 注意：COALESCE 支持多参数
-- 注意：IF 是 MySQL 特有语法
