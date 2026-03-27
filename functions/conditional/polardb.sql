-- PolarDB: 条件函数
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

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

-- IF（MySQL 特有）
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- IFNULL
SELECT IFNULL(phone, 'N/A') FROM users;

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- 类型转换
SELECT CAST('123' AS SIGNED);
SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT('123', SIGNED);

-- ELT / FIELD
SELECT ELT(2, 'a', 'b', 'c');                          -- 'b'
SELECT FIELD('b', 'a', 'b', 'c');                       -- 2

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- ISNULL
SELECT ISNULL(phone) FROM users;

-- 注意事项：
-- 条件函数与 MySQL 完全兼容
