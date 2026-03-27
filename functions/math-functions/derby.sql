-- Apache Derby: Math Functions
--
-- 参考资料:
--   [1] Apache Derby Reference - Built-in Functions
--       https://db.apache.org/derby/docs/10.16/ref/

SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT MOD(17, 5);
SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG10(1000); SELECT LOG(EXP(1));
SELECT SIGN(-42);
SELECT RAND();
SELECT DEGREES(ACOS(-1)); SELECT RADIANS(180);

-- 三角函数
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);

-- 注意：Derby 数学函数有限
-- 限制：无 ROUND 函数（需 Java 实现）
-- 限制：无 POWER 函数（使用 EXP(n * LN(x))）
-- 限制：无 TRUNC/TRUNCATE
-- 限制：无 GREATEST/LEAST
-- 限制：无位运算
