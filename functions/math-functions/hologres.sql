-- Hologres: Math Functions
--
-- 参考资料:
--   [1] Hologres Documentation
--       https://www.alibabacloud.com/help/en/hologres/

-- PostgreSQL 兼容数学函数
SELECT ABS(-42); SELECT CEIL(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100);
SELECT SIGN(-42); SELECT PI(); SELECT RANDOM();

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

-- 注意：Hologres 兼容 PostgreSQL 数学函数
-- 限制：某些高级函数可能不支持
