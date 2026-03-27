-- TimescaleDB: Math Functions
--
-- 参考资料:
--   [1] TimescaleDB Documentation
--       https://docs.timescale.com/
--   [2] PostgreSQL Mathematical Functions
--       https://www.postgresql.org/docs/current/functions-math.html

-- 完全兼容 PostgreSQL 数学函数
SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT 2 ^ 10; SELECT SQRT(144); SELECT CBRT(27);
SELECT |/ 144;                            -- 平方根运算符
SELECT ||/ 27;                            -- 立方根运算符
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI(); SELECT RANDOM();

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT SIND(90); SELECT COSD(0); SELECT TAND(45);
SELECT DEGREES(PI()); SELECT RADIANS(180);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);
SELECT GCD(12, 18); SELECT LCM(12, 18);

SELECT 5 & 3; SELECT 5 | 3; SELECT 5 # 3; SELECT ~5;
SELECT 1 << 4; SELECT 16 >> 2;

-- 注意：TimescaleDB 完全兼容 PostgreSQL 数学函数
-- 注意：支持角度三角函数 (SIND, COSD 等)
-- 注意：^ 是幂运算符, # 是 XOR
