-- openGauss: Type Conversion
--
-- 参考资料:
--   [1] openGauss Documentation
--       https://docs.opengauss.org/

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;
SELECT to_char(123456.789, '999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD');
SELECT to_number('123.45', '999.99'); SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- 注意：openGauss 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
