-- openGauss: Type Conversion
--
-- 参考资料:
--   [1] openGauss Documentation
--       https://docs.opengauss.org/

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;
SELECT to_char(123456.789, '999,999.99'); SELECT to_char(now(), 'YYYY-MM-DD');
SELECT to_number('123.45', '999.99'); SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- 数值转换
SELECT CAST(3.14 AS INTEGER);                       -- 3 (截断)
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT '100'::BIGINT;                                -- 100
SELECT 255::BIT(8);                                  -- 11111111

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT CAST(0 AS BOOLEAN);                           -- false
SELECT 'yes'::BOOLEAN;                               -- true
SELECT 'no'::BOOLEAN;                                -- false
SELECT TRUE::INTEGER;                                -- 1

-- 日期/时间格式化
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_char(now(), 'YYYY"年"MM"月"DD"日"');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);                     -- Unix 时间戳 → TIMESTAMP
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15 00:00:00');

-- 数值格式化
SELECT to_char(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
SELECT to_char(0.5, 'FM990.00%');                    -- 格式化百分比
SELECT to_number('$1,234.56', 'L9,999.99');

-- JSON 转换
SELECT '{"name":"test"}'::JSON;
SELECT '{"name":"test"}'::JSONB;
SELECT CAST('["a","b","c"]' AS JSONB);

-- 隐式转换规则
SELECT 1 + 1.5;                                     -- NUMERIC (整数→NUMERIC)
SELECT 1 + '2';                                     -- 错误：需要显式转换
SELECT 'hello' || 42::TEXT;                          -- 需要显式转 TEXT

-- 数组转换
SELECT ARRAY[1,2,3]::TEXT[];                         -- '{1,2,3}'
SELECT '{1,2,3}'::INTEGER[];                         -- 文本→数组

-- 错误处理（openGauss 无 TRY_CAST，可用函数封装）
-- CREATE FUNCTION safe_cast_int(text) RETURNS INTEGER AS $$
-- BEGIN
--   RETURN $1::INTEGER;
-- EXCEPTION WHEN OTHERS THEN
--   RETURN NULL;
-- END;
-- $$ LANGUAGE plpgsql;

-- 注意：openGauss 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
-- 注意：隐式转换较严格，建议显式 CAST
-- 注意：日期格式使用 PostgreSQL 模板模式 (YYYY, MM, DD, HH24, MI, SS)
