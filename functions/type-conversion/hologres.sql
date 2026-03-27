-- Hologres: Type Conversion
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://www.alibabacloud.com/help/en/hologres/

SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- 数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT '3.14'::NUMERIC(10,2);                        -- 3.14
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 42::FLOAT8;                                   -- 42.0

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT CAST(0 AS BOOLEAN);                           -- false
SELECT 'true'::BOOLEAN;                              -- true
SELECT TRUE::INTEGER;                                -- 1

-- 日期/时间格式化
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_char(CURRENT_DATE, 'YYYY"年"MM"月"DD"日"');
SELECT to_date('20240115', 'YYYYMMDD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);                     -- Unix 时间戳 → TIMESTAMP
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15 00:00:00');

-- 数值格式化
SELECT to_char(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
SELECT to_number('1,234.56', '9,999.99');

-- JSON 转换
SELECT '{"name":"test"}'::JSON;
SELECT '{"name":"test"}'::JSONB;
SELECT CAST('["a","b"]' AS JSONB);

-- 隐式转换规则
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::TEXT;                          -- 需要显式转 TEXT
SELECT 1 + '2'::INTEGER;                            -- 需显式 CAST

-- 数组转换
SELECT ARRAY[1,2,3]::TEXT[];
SELECT '{1,2,3}'::INTEGER[];

-- 错误处理（无 TRY_CAST，转换失败抛错）
-- 建议在应用层处理或使用 PL/pgSQL 封装安全转换函数
-- CREATE FUNCTION safe_cast_int(text) RETURNS INTEGER AS $$
-- BEGIN RETURN $1::INTEGER;
-- EXCEPTION WHEN OTHERS THEN RETURN NULL;
-- END; $$ LANGUAGE plpgsql;

-- 注意：Hologres 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_DATE
-- 注意：日期格式使用 PostgreSQL 模板模式 (YYYY, MM, DD, HH24, MI, SS)
-- 限制：部分高级转换函数可能不支持
-- 限制：无 TRY_CAST, TO_NUMBER 支持有限
