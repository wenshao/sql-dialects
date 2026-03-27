-- SQL Server: 条件函数
--
-- 参考资料:
--   [1] SQL Server T-SQL - CASE
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/case-transact-sql
--   [2] SQL Server T-SQL - IIF
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/logical-functions-iif-transact-sql
--   [3] SQL Server T-SQL - COALESCE
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/coalesce-transact-sql

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

-- IIF（2012+，类似 IF）
SELECT username, IIF(age >= 18, 'adult', 'minor') AS category FROM users;

-- ISNULL（两参数 NULL 替换，SQL Server 特有）
SELECT ISNULL(phone, 'N/A') FROM users;
-- 注意：ISNULL 的返回类型由第一个参数决定，和 COALESCE 不同

-- COALESCE
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- CHOOSE（2012+，按位置选择）
SELECT CHOOSE(2, 'a', 'b', 'c');                        -- 'b'

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CONVERT(INT, '123');
SELECT CONVERT(VARCHAR, GETDATE(), 120);                -- 带格式的日期转换

-- 2012+: TRY_CAST / TRY_CONVERT（转换失败返回 NULL）
SELECT TRY_CAST('abc' AS INT);                          -- NULL（不报错）
SELECT TRY_CONVERT(INT, 'abc');                         -- NULL
SELECT TRY_PARSE('January 2024' AS DATE USING 'en-US'); -- 2012+

-- 2012+: PARSE（文化敏感的类型转换）
SELECT PARSE('$123.45' AS MONEY USING 'en-US');

-- GREATEST / LEAST（2022+）
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1
-- 2022 之前需要用 CASE 或 VALUES 模拟

-- IS NULL 判断
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;
