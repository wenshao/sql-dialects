-- MaxCompute (ODPS): 条件函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Other Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/other-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

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

-- IF（三元条件函数）
SELECT IF(age >= 18, 'adult', 'minor') FROM users;
SELECT IF(amount > 0, amount, 0) FROM orders;

-- NVL（NULL 替换）
SELECT NVL(phone, 'no phone') FROM users;

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

-- DECODE（Oracle 兼容的简单 CASE 替代）
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

-- 类型转换
SELECT CAST('123' AS BIGINT);
SELECT CAST(123 AS STRING);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('true' AS BOOLEAN);

-- 注意：没有 TRY_CAST / SAFE_CAST
-- 转换失败会报错

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IN
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- 类型判断
SELECT TYPEOF(123);                                      -- 类型名
SELECT GETTYPE(123);                                     -- 类型名（别名）

-- 注意：IF 函数支持三参数形式
-- 注意：NVL 兼容 Oracle 语法
-- 注意：DECODE 兼容 Oracle 语法
-- 注意：没有 SAFE_CAST / TRY_CAST（转换失败报错）
-- 注意：没有 :: 转换语法
-- 注意：没有 NULLIFZERO / ZEROIFNULL
