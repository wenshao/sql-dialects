-- CockroachDB: Type Conversion
--
-- 参考资料:
--   [1] CockroachDB Documentation - CAST
--       https://www.cockroachlabs.com/docs/stable/data-types.html#cast-types

-- CAST 和 :: (PostgreSQL 兼容)
SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INT; SELECT '2024-01-15'::DATE;
SELECT '3.14'::DECIMAL; SELECT 'true'::BOOLEAN; SELECT '{"a":1}'::JSONB;

-- 格式化函数
SELECT to_char(123456.789, '999,999.99');
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_number('123,456.78', '999,999.99');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- 隐式转换 (与 PostgreSQL 一致，严格)
SELECT 1 + 1.5;                                 -- DECIMAL
SELECT 'hello' || 42::TEXT;                      -- 需显式转换

-- 注意：CockroachDB 兼容 PostgreSQL 类型转换
-- 注意：支持 CAST 和 :: 运算符
-- 限制：无 TRY_CAST（转换失败抛错）
