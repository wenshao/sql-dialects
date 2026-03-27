-- H2: 条件函数

-- CASE WHEN
SELECT username,
    CASE WHEN age < 18 THEN 'minor' WHEN age < 65 THEN 'adult' ELSE 'senior' END
FROM users;

-- 简单 CASE
SELECT username,
    CASE status WHEN 0 THEN 'inactive' WHEN 1 THEN 'active' ELSE 'unknown' END
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- IFNULL（H2 兼容函数）
SELECT IFNULL(phone, 'N/A') FROM users;

-- NVL（Oracle 兼容）
SELECT NVL(phone, 'N/A') FROM users;

-- NVL2
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                    -- 3
SELECT LEAST(1, 3, 2);                       -- 1

-- DECODE（Oracle 兼容）
SELECT DECODE(status, 0, 'inactive', 1, 'active', 'unknown') FROM users;

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CONVERT('123', INT);                   -- H2 语法
SELECT CAST('2024-01-15' AS DATE);

-- CASEWHEN 函数（H2 特有）
SELECT CASEWHEN(age >= 18, 'adult', 'minor') FROM users;

-- 布尔函数
SELECT IF(age >= 18, 'adult', 'minor') FROM users;

-- 注意：H2 支持多种兼容函数
-- 注意：IFNULL, NVL, NVL2, DECODE 来自不同数据库
-- 注意：CASEWHEN 是 H2 特有简化函数
-- 注意：IF 函数类似 MySQL
