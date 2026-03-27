-- CockroachDB: Math Functions
--
-- 参考资料:
--   [1] CockroachDB Documentation - Math Functions
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators.html#math-functions

-- 基本数学函数 (PostgreSQL 兼容)
SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT SQRT(144); SELECT CBRT(27);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();

-- 随机数
SELECT RANDOM();                          -- 0.0 到 1.0

-- 三角函数
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

-- 位运算
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 # 3;              -- # = XOR
SELECT ~5; SELECT 1 << 4; SELECT 16 >> 2;

-- 注意：CockroachDB 兼容 PostgreSQL 数学函数
-- 注意：XOR 使用 # 运算符（同 PostgreSQL）
