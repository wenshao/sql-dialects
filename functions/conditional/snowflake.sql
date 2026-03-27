-- Snowflake: 条件函数
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Conditional Functions
--       https://docs.snowflake.com/en/sql-reference/functions-conditional
--   [2] Snowflake SQL Reference - CASE
--       https://docs.snowflake.com/en/sql-reference/functions/case

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

-- NVL（COALESCE 的两参数版本，Oracle 兼容）
SELECT NVL(phone, 'no phone') FROM users;

-- NVL2（有值/无值分别返回不同结果）
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;

-- IFF（三元条件，Snowflake 特有）
SELECT IFF(age >= 18, 'adult', 'minor') FROM users;
SELECT IFF(amount > 0, amount, 0) FROM orders;

-- IF（IFF 的别名）
SELECT IF(age >= 18, 'adult', 'minor') FROM users;

-- IFNULL
SELECT IFNULL(phone, 'no phone') FROM users;

-- ZEROIFNULL / NULLIFZERO
SELECT ZEROIFNULL(amount) FROM orders;                    -- NULL -> 0
SELECT NULLIFZERO(amount) FROM orders;                    -- 0 -> NULL

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

-- DECODE（Oracle 兼容的简单 CASE 替代）
SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown') FROM users;

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                   -- :: 转换语法
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

-- 安全转换
SELECT TRY_CAST('abc' AS INTEGER);                        -- NULL（不报错）
SELECT TRY_TO_NUMBER('abc');                              -- NULL
SELECT TRY_TO_DATE('invalid');                            -- NULL
SELECT TRY_TO_TIMESTAMP('invalid');                       -- NULL
SELECT TRY_TO_BOOLEAN('maybe');                           -- NULL

-- TO_* 转换函数
SELECT TO_NUMBER('123.45', 10, 2);
SELECT TO_CHAR(123);
SELECT TO_DATE('2024-01-15');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00');
SELECT TO_BOOLEAN('true');

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- EQUAL_NULL（NULL 安全比较）
SELECT EQUAL_NULL(NULL, NULL);                            -- TRUE
SELECT EQUAL_NULL(1, NULL);                               -- FALSE

-- TYPEOF（返回类型名）
SELECT TYPEOF(123);                                      -- 'INTEGER'
SELECT TYPEOF('hello');                                  -- 'VARCHAR'

-- 注意：IFF 是 Snowflake 推荐的三元条件函数
-- 注意：DECODE 兼容 Oracle 语法
-- 注意：NVL/NVL2 兼容 Oracle 语法
-- 注意：TRY_* 系列是安全转换函数
-- 注意：支持 :: 转换语法
