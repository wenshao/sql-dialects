-- TimescaleDB: Type Conversion
--
-- 参考资料:
--   [1] TimescaleDB Documentation
--       https://docs.timescale.com/
--   [2] PostgreSQL Type Conversion
--       https://www.postgresql.org/docs/current/typeconv.html

-- 完全兼容 PostgreSQL
SELECT CAST(42 AS TEXT); SELECT 42::TEXT; SELECT '42'::INTEGER;
SELECT '2024-01-15'::DATE; SELECT '2024-01-15 10:30:00'::TIMESTAMP;
SELECT '{"a":1}'::JSONB; SELECT 'true'::BOOLEAN;

SELECT to_char(123456.789, 'FM999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_number('123,456.78', '999,999.99');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);                  -- Unix → TIMESTAMP

-- 时间分桶 (TimescaleDB 特有)
SELECT time_bucket('1 hour', now()::TIMESTAMPTZ);
SELECT time_bucket(INTERVAL '1 day', '2024-01-15'::DATE);

-- 注意：TimescaleDB 完全兼容 PostgreSQL 类型转换
-- 注意：time_bucket 接受时间类型参数
