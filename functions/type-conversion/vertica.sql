-- Vertica: Type Conversion
--
-- 参考资料:
--   [1] Vertica Documentation - Data Type Coercion
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Formatting/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

-- 格式化函数
SELECT TO_CHAR(123456.789, '999,999.99'); SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');
SELECT TO_NUMBER('123.45', '999.99');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 更多数值转换
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 42::FLOAT8;                                   -- 42.0

-- 布尔转换
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'true'::BOOLEAN;                              -- true
SELECT TRUE::INTEGER;                                -- 1
SELECT 'yes'::BOOLEAN;                               -- true

-- 日期/时间格式化
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, DD Month YYYY');
SELECT TO_CHAR(NOW(), 'YYYY"年"MM"月"DD"日"');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15 00:00:00');
-- Unix → TIMESTAMP
SELECT TO_TIMESTAMP(1705276800)::TIMESTAMP;

-- 数值格式化
SELECT TO_CHAR(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
SELECT TO_CHAR(0.5, 'FM990.00%');
SELECT TO_CHAR(-1234.5, '9,999.00MI');

-- 区间转换
SELECT INTERVAL '1 day';
SELECT '2 hours 30 minutes'::INTERVAL;

-- 隐式转換规则
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::VARCHAR;                       -- 需要显式转
-- Vertica 隐式转换较严格，与 PostgreSQL 一致

-- 精度处理
SELECT CAST(1.0/3.0 AS NUMERIC(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14

-- 错误处理（无 TRY_CAST）
-- 转换失败直接报错
-- 建议用 CASE + REGEXP_LIKE 预验证
-- SELECT CASE WHEN REGEXP_LIKE(col, '^\d+$') THEN col::INT ELSE NULL END FROM t;

-- 注意：Vertica 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
-- 注意：列式存储，类型转换在查询时执行
-- 限制：无 TRY_CAST
