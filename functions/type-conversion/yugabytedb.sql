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

-- 更多数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 255::BIT(8);                                  -- 11111111

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'yes'::BOOLEAN;                               -- true
SELECT 'no'::BOOLEAN;                                -- false
SELECT TRUE::INTEGER;                                -- 1

-- 日期/时间格式化
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_char(now(), 'YYYY"年"MM"月"DD"日"');
SELECT to_char(now(), 'HH12:MI:SS AM');

-- 数值格式化
SELECT to_char(0.5, 'FM990.00%');                    -- 格式化百分比
SELECT to_char(-1234.5, 'FM9,999.00MI');

-- 区间转换
SELECT INTERVAL '2 hours 30 minutes';
SELECT '1 day'::INTERVAL;
SELECT INTERVAL '1' YEAR;

-- 数组转换
SELECT ARRAY[1,2,3]::TEXT[];
SELECT '{1,2,3}'::INTEGER[];
SELECT ARRAY['a','b','c']::TEXT;                     -- '{a,b,c}'

-- UUID 转换
SELECT gen_random_uuid()::TEXT;                      -- UUID → TEXT
SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID;

-- 隐式转換规则
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::TEXT;                          -- 需要显式转换

-- 分布式注意事项
-- 类型转换在各节点独立执行
-- 建议在应用层做好类型验证，减少集群内转换开销

-- 错误处理（无 TRY_CAST）
-- 可用 PL/pgSQL 封装安全转换
-- CREATE FUNCTION safe_cast_int(text) RETURNS INTEGER AS $$
-- BEGIN RETURN $1::INTEGER;
-- EXCEPTION WHEN OTHERS THEN RETURN NULL;
-- END; $$ LANGUAGE plpgsql;

-- 注意：YugabyteDB 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
-- 注意：分布式架构，类型转换在各 tablet 上执行
-- 限制：无 TRY_CAST
