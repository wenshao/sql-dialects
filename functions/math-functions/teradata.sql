-- Teradata: Math Functions
--
-- 参考资料:
--   [1] Teradata SQL Reference - Numeric Functions
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates/

SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 MOD 5;
SELECT POWER(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100);
SELECT SIGN(-42);
SELECT RANDOM(1, 100);                    -- 范围随机整数

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);
SELECT ACOSH(1); SELECT ASINH(1); SELECT ATANH(0.5);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

-- 位运算
SELECT BITAND(5, 3); SELECT BITOR(5, 3); SELECT BITXOR(5, 3); SELECT BITNOT(5);
SELECT SHIFTLEFT(1, 4); SELECT SHIFTRIGHT(16, 2);

-- 其他
SELECT WIDTH_BUCKET(42, 0, 100, 10);
SELECT NULLIFZERO(0);                     -- 0 转 NULL (Teradata 特有)
SELECT ZEROIFNULL(NULL);                  -- NULL 转 0 (Teradata 特有)

-- 注意：Teradata RANDOM(low, high) 生成范围随机整数
-- 注意：NULLIFZERO / ZEROIFNULL 是 Teradata 特有函数
-- 注意：MOD 支持关键字形式 (a MOD b)
