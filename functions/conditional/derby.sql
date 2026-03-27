-- Derby: 条件函数

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
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- 类型转换
SELECT CAST('123' AS INTEGER) FROM SYSIBM.SYSDUMMY1;
SELECT CAST('2024-01-15' AS DATE) FROM SYSIBM.SYSDUMMY1;
SELECT CAST(123 AS VARCHAR(10)) FROM SYSIBM.SYSDUMMY1;

-- VALUES 表达式
VALUES (CASE WHEN 1 > 0 THEN 'yes' ELSE 'no' END);

-- ============================================================
-- 不支持的条件函数
-- ============================================================

-- 不支持 IFNULL（使用 COALESCE）
-- 不支持 NVL / NVL2
-- 不支持 DECODE
-- 不支持 IF 函数
-- 不支持 GREATEST / LEAST
-- 不支持 IIF

-- 注意：Derby 条件函数比较基础
-- 注意：CASE WHEN 和 COALESCE 是主要的条件工具
-- 注意：NULLIF 可用
-- 注意：GREATEST/LEAST 需要用 CASE WHEN 模拟
