-- Materialize: Type Conversion
--
-- 参考资料:
--   [1] Materialize Documentation - CAST
--       https://materialize.com/docs/sql/functions/#casts

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INT; SELECT '2024-01-15'::DATE;
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);

-- 注意：Materialize 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, to_char, to_timestamp
-- 限制：无 TRY_CAST
