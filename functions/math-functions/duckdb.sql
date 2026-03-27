-- DuckDB: Math Functions
--
-- 参考资料:
--   [1] DuckDB Documentation - Numeric Functions
--       https://duckdb.org/docs/sql/functions/numeric

SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT POW(2, 10); SELECT SQRT(144); SELECT CBRT(27);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100); SELECT LOG2(1024); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();
SELECT RANDOM();                          -- 0.0 到 1.0
SELECT SETSEED(0.5);

-- 三角函数
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

-- 位运算
SELECT 5 & 3; SELECT 5 | 3; SELECT xor(5, 3);
SELECT ~5; SELECT 1 << 4; SELECT 16 >> 2;
SELECT BIT_COUNT(7);

-- 其他
SELECT FACTORIAL(5);
SELECT GCD(12, 18); SELECT LCM(12, 18);
SELECT GAMMA(5);                          -- 24.0 (伽马函数)
SELECT LGAMMA(100);                       -- 对数伽马函数
SELECT EVEN(5);                           -- 6 (向上取偶)

-- 注意：DuckDB 兼容 PostgreSQL 数学函数
-- 注意：提供 GCD, LCM, FACTORIAL, GAMMA 等扩展
-- 注意：LOG(x) 以 10 为底（同 PostgreSQL）
