-- Trino: 条件函数
--
-- 参考资料:
--   [1] Trino - Conditional Expressions
--       https://trino.io/docs/current/functions/conditional.html
--   [2] Trino - Functions and Operators
--       https://trino.io/docs/current/functions.html

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

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                                -- 3
SELECT LEAST(1, 3, 2);                                   -- 1

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('true' AS BOOLEAN);
SELECT CAST(123 AS VARCHAR);

-- 安全转换
SELECT TRY_CAST('abc' AS INTEGER);                        -- NULL（不报错）
SELECT TRY_CAST('2024-13-01' AS DATE);                    -- NULL
SELECT TRY_CAST('true' AS BOOLEAN);                       -- TRUE

-- TRY 函数（捕获表达式错误）
SELECT TRY(1 / 0);                                       -- NULL（不报错）
SELECT TRY(CAST('abc' AS INTEGER));                       -- NULL

-- TYPEOF（返回类型名）
SELECT TYPEOF(123);                                      -- 'integer'
SELECT TYPEOF('hello');                                  -- 'varchar(5)'
SELECT TYPEOF(CURRENT_TIMESTAMP);                        -- 'timestamp with time zone'

-- IS 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IS DISTINCT FROM（NULL 安全比较）
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;  -- 等同 IS NULL

-- IN
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai');
SELECT * FROM users WHERE city NOT IN ('Beijing', 'Shanghai');

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- TRANSFORM（数组转换条件）
SELECT TRANSFORM(ARRAY[1, 2, 3], x -> IF(x > 1, x * 10, x));  -- [1, 20, 30]

-- REDUCE（数组归约）
SELECT REDUCE(ARRAY[1, 2, 3], 0, (s, x) -> s + x, s -> s);    -- 6

-- 注意：TRY_CAST 是安全类型转换
-- 注意：TRY 函数可以包装任何表达式
-- 注意：IS DISTINCT FROM 是 NULL 安全比较（SQL 标准）
-- 注意：支持 Lambda 表达式用于数组操作
-- 注意：没有 DECODE 函数
-- 注意：没有 NVL / NVL2 函数
-- 注意：没有 :: 转换语法
