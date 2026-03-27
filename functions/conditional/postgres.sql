-- PostgreSQL: 条件函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Conditional Expressions
--       https://www.postgresql.org/docs/current/functions-conditional.html
--   [2] PostgreSQL Documentation - CASE
--       https://www.postgresql.org/docs/current/functions-conditional.html#FUNCTIONS-CASE

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

-- GREATEST / LEAST
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                                  -- PostgreSQL 特有的 :: 语法
SELECT '2024-01-15'::DATE;
SELECT CAST('true' AS BOOLEAN);

-- 安全转换（不报错，返回 NULL）
-- 没有内置的 TRY_CAST，但可以自己写函数
-- 或者用正则判断：
SELECT CASE WHEN '123a' ~ '^\d+$' THEN '123a'::INTEGER ELSE NULL END;

-- 布尔条件表达式（PostgreSQL 特有的简洁用法）
SELECT username, (age >= 18) AS is_adult FROM users;

-- DISTINCT FROM（NULL 安全的比较）
SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';    -- NULL ≠ 'unknown'
SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;     -- 等同 IS NULL

-- num_nulls / num_nonnulls（9.6+）
SELECT num_nulls(phone, email, city) FROM users;         -- NULL 参数个数
SELECT num_nonnulls(phone, email, city) FROM users;      -- 非 NULL 参数个数
