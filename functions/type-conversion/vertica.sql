-- Vertica: Type Conversion
--
-- 参考资料:
--   [1] Vertica Documentation - Data Type Coercion
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Formatting/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

-- 格式化函数
SELECT TO_CHAR(123456.789, '999,999.99'); SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');
SELECT TO_NUMBER('123.45', '999.99');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 注意：Vertica 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
-- 限制：无 TRY_CAST
