-- MaxCompute: Math Functions
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - Math Functions
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/mathematical-functions

SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5);
SELECT POWER(2, 10); SELECT POW(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(10, 1000);
SELECT SIGN(-42);
SELECT RAND(); SELECT RAND(42);

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1);
SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

-- 位运算
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 ^ 3; SELECT ~5;
SELECT SHIFTLEFT(1, 4); SELECT SHIFTRIGHT(16, 2);

-- 注意：MaxCompute 数学函数与 Hive 类似
-- 注意：LOG(base, x) 底数在前
-- 限制：无 PI() 函数
