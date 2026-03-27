-- Hologres: Type Conversion
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://www.alibabacloud.com/help/en/hologres/

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- 注意：Hologres 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_DATE
-- 限制：部分高级转换函数可能不支持
