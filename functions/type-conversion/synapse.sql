-- Azure Synapse: Type Conversion
--
-- 参考资料:
--   [1] Synapse SQL - CAST and CONVERT
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);

-- CONVERT 带样式码
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);     -- 'YYYY-MM-DD'
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);     -- 'MM/DD/YYYY'

-- TRY_CAST / TRY_CONVERT
SELECT TRY_CAST('abc' AS INT);                  -- NULL
SELECT TRY_CONVERT(INT, 'abc');                  -- NULL

-- FORMAT
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd');

-- 注意：与 SQL Server 类型转换一致
-- 注意：支持 CAST, CONVERT, TRY_CAST, TRY_CONVERT, FORMAT
-- 限制：无 ::, TO_NUMBER, TO_CHAR
