-- Greenplum: Type Conversion
--
-- 参考资料:
--   [1] Greenplum Documentation
--       https://docs.vmware.com/en/VMware-Greenplum/

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

SELECT to_char(123456.789, '999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_number('123,456.78', '999,999.99');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 更多数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 42::FLOAT8;                                   -- 42.0

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT CAST(0 AS BOOLEAN);                           -- false
SELECT 'yes'::BOOLEAN;                               -- true
SELECT TRUE::INTEGER;                                -- 1

-- 日期/时间格式化
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_char(now(), 'YYYY"年"MM"月"DD"日"');
SELECT to_timestamp(1705276800);                     -- Unix → TIMESTAMP
SELECT EXTRACT(EPOCH FROM now());                    -- TIMESTAMP → Unix

-- 数值格式化
SELECT to_char(0.5, 'FM990.00%');                    -- 格式化百分比
SELECT to_char(-1234.5, 'FM9,999.00MI');             -- 负号后置

-- JSON 转换 (Greenplum 6+)
SELECT '{"name":"test"}'::JSON;

-- 隐式转换规则
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::TEXT;                          -- 需要显式转换
-- SELECT 1 + '2';                                   -- 错误

-- 数组转换
SELECT ARRAY[1,2,3]::TEXT[];
SELECT '{1,2,3}'::INTEGER[];

-- 分布式环境中的注意事项
-- DISTRIBUTED BY 列的类型转换可能影响数据分布
-- 建议在 ETL 阶段做好类型转换，避免查询时转换

-- 错误处理（无 TRY_CAST）
-- 转换失败直接报错，建议用 PL/pgSQL 封装安全转换
-- CREATE FUNCTION safe_cast_int(text) RETURNS INTEGER AS $$
-- BEGIN RETURN $1::INTEGER;
-- EXCEPTION WHEN OTHERS THEN RETURN NULL;
-- END; $$ LANGUAGE plpgsql;

-- 注意：Greenplum 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
-- 注意：MPP 环境下类型转换在每个 Segment 独立执行
-- 限制：无 TRY_CAST
