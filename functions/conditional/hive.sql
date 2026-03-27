-- Hive: 条件函数
--
-- 参考资料:
--   [1] Apache Hive - Conditional Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-ConditionalFunctions
--   [2] Apache Hive Language Manual - UDF
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

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

-- NVL（NULL 替换，0.11+）
SELECT NVL(phone, 'no phone') FROM users;

-- ISNULL / ISNOTNULL
SELECT ISNULL(phone) FROM users;                          -- 返回 BOOLEAN
SELECT ISNOTNULL(phone) FROM users;                       -- 返回 BOOLEAN

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

-- DECODE: Hive 不支持 Oracle 风格的 DECODE 函数
-- 使用 CASE WHEN 替代

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS STRING);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('true' AS BOOLEAN);

-- 注意：没有 TRY_CAST / SAFE_CAST
-- 转换失败返回 NULL（不报错，与多数数据库不同）

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IN
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- 布尔判断
SELECT * FROM users WHERE NOT active;
SELECT * FROM users WHERE age > 18 AND city = 'Beijing';
SELECT * FROM users WHERE age < 18 OR city = 'Shanghai';

-- ASSERT_TRUE（断言，调试用）
SELECT ASSERT_TRUE(age > 0) FROM users;                   -- 为 FALSE 时报错

-- 隐式类型转换规则
-- STRING 可以隐式转为数值（'123' 可以参与数值运算）
-- BOOLEAN 不能隐式转换
-- TINYINT -> SMALLINT -> INT -> BIGINT -> FLOAT -> DOUBLE

-- 注意：IF 函数是 Hive 的基本条件函数
-- 注意：NVL 在 0.11 引入
-- 注意：CAST 失败返回 NULL（静默失败）
-- 注意：没有 :: 转换语法
-- 注意：没有 DECODE 函数（使用 CASE WHEN）
