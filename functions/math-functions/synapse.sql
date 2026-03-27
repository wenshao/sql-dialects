-- Azure Synapse: Math Functions
--
-- 参考资料:
--   [1] Synapse SQL - Mathematical Functions
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

SELECT ABS(-42); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT ROUND(3.14159, 2, 1);   -- 截断模式
SELECT 17 % 5;
SELECT POWER(2, 10); SELECT SQRT(144); SELECT SQUARE(12);
SELECT EXP(1); SELECT LOG(EXP(1)); SELECT LOG(1024, 2); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();
SELECT RAND(); SELECT RAND(42);

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATN2(1, 1);
SELECT COT(1);
SELECT DEGREES(PI()); SELECT RADIANS(180.0);

-- 位运算
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 ^ 3; SELECT ~5;

-- 注意：与 SQL Server 数学函数一致
-- 注意：用 CEILING（无 CEIL），ATN2（非 ATAN2）
-- 注意：^ 是 XOR（幂用 POWER）
-- 限制：GREATEST/LEAST 可能不支持（取决于版本）
