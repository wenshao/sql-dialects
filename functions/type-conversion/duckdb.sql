-- DuckDB: Type Conversion
--
-- 参考资料:
--   [1] DuckDB Documentation - CAST / TRY_CAST
--       https://duckdb.org/docs/sql/expressions/cast

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('3.14' AS DOUBLE);

-- :: 运算符
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

-- TRY_CAST (安全转换)
SELECT TRY_CAST('abc' AS INTEGER);              -- NULL
SELECT TRY_CAST('42' AS INTEGER);               -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL

-- 格式化
SELECT strftime(CURRENT_DATE, '%Y-%m-%d');
SELECT strptime('2024-01-15', '%Y-%m-%d');
SELECT format('{:.2f}', 3.14159);               -- '3.14'

-- 隐式转换
SELECT 1 + 1.5;                                 -- DOUBLE
SELECT 'hello' || 42::VARCHAR;

-- 注意：DuckDB 支持 CAST, ::, TRY_CAST
-- 注意：strftime/strptime 用于日期格式化
-- 注意：format 使用 Python 风格格式化
