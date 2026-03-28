-- StarRocks: 数学函数
--
-- 参考资料:
--   [1] StarRocks Documentation - Math Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- ============================================================
-- 与 Doris 完全相同(同源，MySQL 兼容)
-- ============================================================
SELECT ABS(-42), CEIL(4.3), FLOOR(4.7);
SELECT ROUND(3.14159, 2), TRUNCATE(3.14159, 2);
SELECT MOD(17, 5), POWER(2, 10), SQRT(144);
SELECT EXP(1), LN(EXP(1)), LOG2(1024), LOG10(1000);
SELECT SIGN(-42), PI(), RAND();
SELECT GREATEST(1, 5, 3), LEAST(1, 5, 3);

SELECT SIN(0), COS(0), TAN(0);
SELECT ASIN(1), ACOS(1), ATAN(1);
SELECT DEGREES(PI()), RADIANS(180);

SELECT BITAND(5, 3), BITOR(5, 3), BITXOR(5, 3), BITNOT(5);

-- StarRocks vs Doris: 数学函数完全相同。
