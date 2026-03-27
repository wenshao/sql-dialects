-- Teradata: Type Conversion
--
-- 参考资料:
--   [1] Teradata SQL Reference - CAST
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates/

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);

-- Teradata 格式化
SELECT CAST(CURRENT_DATE AS FORMAT 'YYYY-MM-DD');
SELECT CAST(CURRENT_TIMESTAMP AS FORMAT 'YYYY-MM-DDBHH:MI:SS');

-- TO_CHAR / TO_DATE / TO_NUMBER (Oracle 兼容模式)
SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_NUMBER('123.45');

-- TRY_CAST                                      -- 16.20+
SELECT TRY_CAST('abc' AS INTEGER);               -- NULL
SELECT TRY_CAST('42' AS INTEGER);                -- 42

-- 注意：Teradata 支持 CAST, FORMAT 修饰符, TO_* 函数
-- 注意：Teradata 16.20+ 支持 TRY_CAST
-- 注意：FORMAT 修饰符是 Teradata 特有
-- 限制：无 ::, CONVERT (SQL Server 风格)
