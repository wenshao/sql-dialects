-- ksqlDB: Math Functions
--
-- 参考资料:
--   [1] ksqlDB Function Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/

SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159);
SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1));
SELECT SIGN(-42);
SELECT RANDOM();

-- GREATEST / LEAST (通过 CASE 模拟)

-- 注意：ksqlDB 数学函数非常有限
-- 注意：面向流处理，不需要完整的数学库
-- 限制：无三角函数
-- 限制：无 POWER, LOG, MOD 等
-- 限制：无位运算
