-- Apache Derby: Math Functions
--
-- 参考资料:
--   [1] Apache Derby Reference - Built-in Functions
--       https://db.apache.org/derby/docs/10.16/ref/

-- ============================================================
-- 基本数学函数
-- ============================================================
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT CEILING(4.3);                      -- 5            (CEIL 同义)
SELECT FLOOR(4.7);                        -- 4
SELECT MOD(17, 5);                        -- 2

-- ============================================================
-- 根、指数、对数
-- ============================================================
SELECT SQRT(144);                         -- 12
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(EXP(1));                        -- 1.0          (自然对数)
SELECT LOG(EXP(1));                       -- 1.0          (自然对数，同 LN)
SELECT LOG10(1000);                       -- 3

-- 模拟 POWER: EXP(n * LN(x))
SELECT EXP(10 * LN(2));                  -- ≈ 1024       (2^10)
SELECT EXP(0.5 * LN(144));              -- ≈ 12         (144^0.5 = SQRT)

-- ============================================================
-- 符号和随机数
-- ============================================================
SELECT SIGN(-42);                         -- -1
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
SELECT RAND();                            -- 0.0 到 1.0 之间

-- ============================================================
-- 三角函数（弧度）
-- ============================================================
SELECT SIN(0);                            -- 0
SELECT COS(0);                            -- 1
SELECT TAN(ACOS(-1)/4);                  -- ≈ 1.0        (tan(π/4))
SELECT ASIN(1);                           -- π/2
SELECT ACOS(1);                           -- 0
SELECT ATAN(1);                           -- π/4
SELECT ATAN2(1, 1);                       -- π/4

-- 弧度角度转换
SELECT DEGREES(ACOS(-1));                 -- 180          (π → 180°)
SELECT RADIANS(180);                      -- π

-- ============================================================
-- Java UDF 补充缺失函数
-- ============================================================
-- ROUND:
-- CREATE FUNCTION round_num(val DOUBLE, places INT)
--     RETURNS DOUBLE
--     LANGUAGE JAVA
--     EXTERNAL NAME 'com.example.MathUDF.round'
--     PARAMETER STYLE JAVA NO SQL;

-- POWER:
-- CREATE FUNCTION power(base DOUBLE, exp DOUBLE)
--     RETURNS DOUBLE
--     LANGUAGE JAVA
--     EXTERNAL NAME 'java.lang.Math.pow'
--     PARAMETER STYLE JAVA NO SQL;

-- 注意：Derby 数学函数有限但核心函数齐全
-- 注意：LOG 等同于 LN（自然对数），不同于 PostgreSQL
-- 注意：可通过 Java UDF 扩展缺失函数
-- 限制：无 ROUND 函数（需 Java UDF 或 CAST 模拟）
-- 限制：无 POWER/POW 函数（使用 EXP(n * LN(x)) 模拟）
-- 限制：无 TRUNC/TRUNCATE
-- 限制：无 PI() 函数（使用 ACOS(-1) 代替）
-- 限制：无 GREATEST/LEAST
-- 限制：无位运算
-- 限制：无 CBRT 立方根
