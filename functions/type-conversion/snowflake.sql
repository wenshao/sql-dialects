-- Snowflake: Type Conversion
--
-- 参考资料:
--   [1] Snowflake Documentation - Conversion Functions
--       https://docs.snowflake.com/en/sql-reference/functions-conversion
--   [2] Snowflake Documentation - TRY_CAST
--       https://docs.snowflake.com/en/sql-reference/functions/try_cast

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('3.14' AS FLOAT); SELECT CAST('3.14' AS NUMBER(10,2));

-- :: 运算符
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

-- TRY_CAST (安全转换)
SELECT TRY_CAST('abc' AS INTEGER);              -- NULL
SELECT TRY_CAST('42' AS INTEGER);               -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL

-- TO_* 转换函数
SELECT TO_VARCHAR(42); SELECT TO_VARCHAR(CURRENT_DATE(), 'YYYY-MM-DD');
SELECT TO_NUMBER('123.45', '999.99'); SELECT TO_DECIMAL('3.14', 10, 2);
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS');

-- TRY_TO_* (安全版本)
SELECT TRY_TO_NUMBER('abc');                     -- NULL
SELECT TRY_TO_DATE('bad-date');                 -- NULL
SELECT TRY_TO_TIMESTAMP('bad-ts');              -- NULL
SELECT TRY_TO_DECIMAL('abc', 10, 2);            -- NULL
SELECT TRY_TO_BOOLEAN('abc');                   -- NULL

-- 格式化
SELECT TO_VARCHAR(CURRENT_TIMESTAMP(), 'DY, DD MON YYYY HH24:MI:SS');

-- 注意：Snowflake 支持 CAST, ::, TRY_CAST
-- 注意：支持完整的 TO_* 和 TRY_TO_* 系列
-- 注意：TRY_TO_* 是 Snowflake 特有的安全转换系列
