-- Firebird: Type Conversion
--
-- 参考资料:
--   [1] Firebird Language Reference - CAST
--       https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('10:30:00' AS TIME); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- 格式化 (无内置格式化函数，需在应用层处理)
-- 使用 LPAD/SUBSTRING 等手动格式化

-- 隐式转换
SELECT '42' || 0;                                -- 文本拼接（不自动转数字）

-- 注意：Firebird 主要使用标准 CAST
-- 限制：无 TRY_CAST, CONVERT, ::, TO_NUMBER, TO_CHAR, TO_DATE
-- 限制：无内置日期/数值格式化函数
