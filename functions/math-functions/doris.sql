-- Apache Doris: 数学函数
--
-- 参考资料:
--   [1] Doris Documentation - Math Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/math-functions/

-- ============================================================
-- 1. 基本数学 (MySQL 兼容)
-- ============================================================
SELECT ABS(-42), CEIL(4.3), FLOOR(4.7);
SELECT ROUND(3.14159, 2), TRUNCATE(3.14159, 2);
SELECT MOD(17, 5), 17 % 5;
SELECT POWER(2, 10), SQRT(144);
SELECT EXP(1), LN(EXP(1)), LOG2(1024), LOG10(1000);
SELECT SIGN(-42), PI();
SELECT RAND(), RAND(42);
SELECT GREATEST(1, 5, 3), LEAST(1, 5, 3);

-- ============================================================
-- 2. 三角函数
-- ============================================================
SELECT SIN(0), COS(0), TAN(0);
SELECT ASIN(1), ACOS(1), ATAN(1), ATAN2(1, 1);
SELECT DEGREES(PI()), RADIANS(180);

-- ============================================================
-- 3. 位运算
-- ============================================================
SELECT BITAND(5, 3), BITOR(5, 3), BITXOR(5, 3), BITNOT(5);

-- 对比:
--   Doris:     函数形式 BITAND(a, b)
--   MySQL:     运算符形式 a & b
--   StarRocks: 与 Doris 相同(同源)
--   ClickHouse: bitAnd(a, b) 或 a & b(两种都支持)
