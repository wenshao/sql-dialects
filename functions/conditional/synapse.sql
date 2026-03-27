-- Azure Synapse: 条件函数
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

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
SELECT COALESCE(phone, email, N'unknown') FROM users;

-- NULLIF
SELECT NULLIF(age, 0) FROM users;

-- ISNULL（T-SQL 特有，同 NVL）
SELECT ISNULL(phone, N'unknown') FROM users;

-- IIF（T-SQL 三元表达式）
SELECT IIF(age >= 18, 'adult', 'minor') FROM users;

-- CHOOSE（按索引选择）
SELECT CHOOSE(status + 1, 'inactive', 'active', 'deleted') FROM users;

-- GREATEST / LEAST（SQL Server 2022+，Synapse 可能不支持）
-- SELECT GREATEST(1, 3, 2);
-- 替代方案：
SELECT (SELECT MAX(v) FROM (VALUES (col1), (col2), (col3)) AS t(v));

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(N'123.45' AS DECIMAL(10, 2));
SELECT CONVERT(INT, '123');                          -- T-SQL 风格
SELECT CONVERT(NVARCHAR, 123);

-- 安全转换
SELECT TRY_CAST('abc' AS INT);                       -- 返回 NULL
SELECT TRY_CONVERT(INT, 'abc');                      -- 返回 NULL

-- IS NULL / IS NOT NULL
SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- BETWEEN
SELECT * FROM users WHERE age BETWEEN 18 AND 65;

-- IN / NOT IN
SELECT * FROM users WHERE status IN (0, 1, 2);
SELECT * FROM users WHERE city NOT IN (N'Beijing', N'Shanghai');

-- 条件表达式用于更新
UPDATE users SET status = CASE WHEN age >= 18 THEN 1 ELSE 0 END;

-- 复合条件
SELECT username,
    IIF(status = 1 AND age >= 18,
        IIF(age >= 65, 'senior active', 'active'),
        'inactive') AS category
FROM users;

-- 注意：ISNULL 是 T-SQL 特有（不是 IS NULL 判断）
-- 注意：IIF 是简洁的三元表达式
-- 注意：CHOOSE 按 1-based 索引选择值
-- 注意：TRY_CAST / TRY_CONVERT 是安全转换（不报错）
-- 注意：没有 BOOLEAN 类型（用 BIT 0/1）
-- 注意：没有 IS DISTINCT FROM 语法
-- 注意：GREATEST / LEAST 可能不可用，需要替代方案
