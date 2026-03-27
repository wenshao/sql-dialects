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

-- 更多数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 255::BIT(8);                                  -- 11111111

-- 布尔转換
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'yes'::BOOLEAN;                               -- true
SELECT TRUE::INTEGER;                                -- 1

-- 日期/時間格式化
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_char(now(), 'YYYY"年"MM"月"DD"日"');
SELECT to_char(now(), 'HH12:MI:SS AM');

-- 数值格式化
SELECT to_char(1234567.89, 'FM9,999,999.00');
SELECT to_char(0.5, 'FM990.00%');

-- 更多 time_bucket 示例
SELECT time_bucket('5 minutes', now()::TIMESTAMPTZ);
SELECT time_bucket('1 week', '2024-01-15'::DATE);
SELECT time_bucket(INTERVAL '1 month', '2024-01-15'::DATE);

-- 时间戳精度
SELECT now()::TIMESTAMP;                             -- 不含时区
SELECT now()::TIMESTAMPTZ;                           -- 含时区

-- JSON 转換
SELECT '{"sensor":"temp","value":23.5}'::JSONB;
SELECT CAST('["a","b"]' AS JSONB);

-- 数组转換
SELECT ARRAY[1,2,3]::TEXT[];
SELECT '{1,2,3}'::INTEGER[];

-- 错误処理（无 TRY_CAST）
-- CREATE FUNCTION safe_cast_int(text) RETURNS INTEGER AS $$
-- BEGIN RETURN $1::INTEGER;
-- EXCEPTION WHEN OTHERS THEN RETURN NULL;
-- END; $$ LANGUAGE plpgsql;

-- 注意：TimescaleDB 完全兼容 PostgreSQL 类型转换
-- 注意：time_bucket 接受时间类型参数
-- 注意：时序数据中 TIMESTAMPTZ 是推荐的时间类型
-- 注意：连续聚合中的类型转换在物化时执行
