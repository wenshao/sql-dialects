-- YugabyteDB: Type Conversion
--
-- 参考资料:
--   [1] YugabyteDB Documentation
--       https://docs.yugabyte.com/preview/api/ysql/exprs/

-- 完全兼容 PostgreSQL
SELECT CAST(42 AS TEXT); SELECT 42::TEXT; SELECT '42'::INTEGER;
SELECT '2024-01-15'::DATE; SELECT '2024-01-15 10:30:00'::TIMESTAMP;
SELECT 'true'::BOOLEAN; SELECT '{"a":1}'::JSONB;

SELECT to_char(123456.789, 'FM999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_number('123,456.78', '999,999.99');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);

-- 注意：YugabyteDB 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
-- 限制：无 TRY_CAST
