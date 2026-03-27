-- Snowflake: Math Functions
--
-- 参考资料:
--   [1] Snowflake Documentation - Numeric Functions
--       https://docs.snowflake.com/en/sql-reference/functions-numeric

SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNCATE(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT POW(2, 10); SELECT SQRT(144); SELECT CBRT(27);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(10, 1000);
SELECT SIGN(-42); SELECT PI();
SELECT RANDOM();                          -- 整数随机数 (INT)
SELECT UNIFORM(1, 100, RANDOM());        -- 1 到 100 均匀分布
SELECT NORMAL(0, 1, RANDOM());           -- 正态分布

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT COT(1);
SELECT DEGREES(PI()); SELECT RADIANS(180);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);
SELECT ASINH(1); SELECT ACOSH(1); SELECT ATANH(0.5);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

SELECT BITAND(5, 3); SELECT BITOR(5, 3); SELECT BITXOR(5, 3);
SELECT BITNOT(5);
SELECT BITSHIFTLEFT(1, 4); SELECT BITSHIFTRIGHT(16, 2);

-- 其他
SELECT DIV0(10, 0);                       -- 0 (安全除法)
SELECT DIV0NULL(10, 0);                   -- NULL
SELECT HAVERSINE(40.7, -74.0, 51.5, -0.1); -- 球面距离
SELECT FACTORIAL(5);                       -- 120
SELECT SQUARE(5);                          -- 25
SELECT WIDTH_BUCKET(42, 0, 100, 10);

-- 注意：RANDOM() 返回整数，使用 UNIFORM() 生成范围内随机数
-- 注意：DIV0 / DIV0NULL 安全除法函数
-- 注意：HAVERSINE 计算球面距离
-- 注意：LOG(base, x) 底数在前
