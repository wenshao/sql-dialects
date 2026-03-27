-- DuckDB: Type Conversion
--
-- 参考资料:
--   [1] DuckDB Documentation - CAST / TRY_CAST
--       https://duckdb.org/docs/sql/expressions/cast

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('3.14' AS DOUBLE);

-- :: 运算符
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

-- TRY_CAST (安全转换)
SELECT TRY_CAST('abc' AS INTEGER);              -- NULL
SELECT TRY_CAST('42' AS INTEGER);               -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL

-- 格式化
SELECT strftime(CURRENT_DATE, '%Y-%m-%d');
SELECT strptime('2024-01-15', '%Y-%m-%d');
SELECT format('{:.2f}', 3.14159);               -- '3.14'

-- 隐式转换
SELECT 1 + 1.5;                                 -- DOUBLE
SELECT 'hello' || 42::VARCHAR;

-- 更多数值转换
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT TRUE::INTEGER;                                -- 1
SELECT 0::BOOLEAN;                                   -- false
SELECT CAST(3.14 AS HUGEINT);                        -- 3

-- TRY_CAST 详细示例
SELECT TRY_CAST('hello' AS INTEGER);                 -- NULL
SELECT TRY_CAST('2024-99-99' AS DATE);               -- NULL
SELECT TRY_CAST('' AS INTEGER);                      -- NULL
SELECT TRY_CAST('3.14' AS DECIMAL(10,2));            -- 3.14

-- 日期/时間格式化
SELECT strftime(CURRENT_DATE, '%Y-%m-%d');
SELECT strftime(CURRENT_DATE, '%d/%m/%Y');
SELECT strftime(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%M:%S');
SELECT strftime(CURRENT_DATE, '%A, %B %d, %Y');
SELECT strptime('15/01/2024', '%d/%m/%Y');
SELECT strptime('Jan 15, 2024', '%b %d, %Y');

-- 数値格式化
SELECT format('{:.2f}', 3.14159);                    -- '3.14'
SELECT format('{:,}', 1234567);                      -- '1,234,567'
SELECT format('{:.0%}', 0.15);                       -- '15%'
SELECT printf('%.2f', 3.14159);                      -- '3.14'

-- 日期部分提取
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT date_part('day', CURRENT_DATE);

-- 区間転換
SELECT INTERVAL '2 hours 30 minutes';
SELECT '1 day'::INTERVAL;
SELECT CURRENT_DATE + INTERVAL 1 DAY;

-- LIST (数組) 転換
SELECT [1, 2, 3]::VARCHAR[];
SELECT list_value(1, 2, 3);

-- STRUCT 転換
SELECT {'name': 'test', 'value': 42};
SELECT CAST(ROW(1, 'abc') AS STRUCT(id INTEGER, name VARCHAR));

-- JSON 転換
SELECT '{"a":1}'::JSON;
SELECT json_extract('{"a":1}', '$.a');

-- 注意：DuckDB 支持 CAST, ::, TRY_CAST
-- 注意：strftime/strptime 用于日期格式化（C strftime 格式码）
-- 注意：format 使用 Python 风格格式化 ({:.2f})
-- 注意：原生支持 LIST, STRUCT, MAP, UNION 类型
