-- PostgreSQL: 数学函数
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Mathematical Functions
--       https://www.postgresql.org/docs/current/functions-math.html
--   [2] PostgreSQL Source - float.c, numeric.c
--       https://github.com/postgres/postgres/blob/master/src/backend/utils/adt/float.c

-- ============================================================
-- 1. 基本数学函数
-- ============================================================

SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5 (CEILING 同义)
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT TRUNC(3.14159, 2);                 -- 3.14 (截断，不四舍五入)
SELECT MOD(17, 5);                        -- 2
SELECT 17 % 5;                            -- 2 (运算符形式)
SELECT SIGN(-42);                         -- -1

-- ============================================================
-- 2. PostgreSQL 特有的数学运算符
-- ============================================================

-- 幂运算: ^ (注意: 不是 XOR！PostgreSQL 用 # 做 XOR)
SELECT 2 ^ 10;                            -- 1024
SELECT POWER(2, 10);                      -- 1024 (函数形式)

-- 平方根/立方根运算符 (PostgreSQL 独有)
SELECT |/ 144;                            -- 12 (平方根运算符)
SELECT SQRT(144);                         -- 12 (函数形式)
SELECT ||/ 27;                            -- 3  (立方根运算符)
SELECT CBRT(27);                          -- 3  (函数形式)

-- 设计分析: 为什么 ^ 是幂运算而非 XOR
--   这是历史设计选择——PostgreSQL 继承自 POSTGRES 项目（1986年）。
--   数学中 ^ 表示幂运算，PostgreSQL 选择了数学惯例。
--   XOR 使用 # 运算符: SELECT 5 # 3; → 6
--   对比:
--     MySQL/SQL Server: ^ 是 XOR（遵循 C 语言惯例）
--     Oracle:           无 ^ 运算符（用 POWER 函数）
--   迁移陷阱: MySQL 的 2 ^ 10 = 8 (XOR)，PostgreSQL 的 2 ^ 10 = 1024 (幂)

-- ============================================================
-- 3. 对数与指数
-- ============================================================

SELECT EXP(1);                            -- e ≈ 2.718281828
SELECT LN(2.718281828);                   -- ≈ 1.0 (自然对数)
SELECT LOG(100);                          -- 2.0 (以10为底, 注意!)
SELECT LOG(2, 1024);                      -- 10  (自定义底数)
SELECT LOG10(1000);                       -- 3.0  (12+, 显式以10为底)

-- 设计陷阱: LOG(x) 的底数
--   PostgreSQL: LOG(x) 以 10 为底（历史原因）
--   MySQL:      LOG(x) 以 e 为底（自然对数），LOG10(x) 以 10 为底
--   数学惯例:   log(x) 通常指自然对数 ln(x)
--   PostgreSQL 的 LOG(x)=log10(x) 违反数学惯例，但已无法更改（兼容性）

-- ============================================================
-- 4. 随机数
-- ============================================================

SELECT RANDOM();                          -- [0.0, 1.0) 之间的随机 DOUBLE
SELECT FLOOR(RANDOM() * 100 + 1)::INT;   -- 1-100 随机整数
SELECT SETSEED(0.5);                      -- 设置随机种子（可重现）

-- 实现: 每个 backend 维护独立的随机数状态（线程安全）
-- 注意: RANDOM() 不是加密安全的——加密场景用 pgcrypto 的 gen_random_bytes()

-- ============================================================
-- 5. 三角/双曲函数
-- ============================================================

SELECT SIN(0), COS(0), TAN(PI()/4);      -- 弧度版
SELECT SIND(90), COSD(0), TAND(45);       -- 角度版 (7.2+, PostgreSQL 独有!)
SELECT DEGREES(PI()), RADIANS(180);       -- 弧度↔角度转换
SELECT SINH(1), COSH(1), TANH(1);         -- 双曲函数 (12+)
SELECT PI();                              -- 3.14159265358979

-- 角度版三角函数 (SIND, COSD, TAND 等) 是 PostgreSQL 独有的:
-- 其他数据库只有弧度版，需要手动 RADIANS/DEGREES 转换

-- ============================================================
-- 6. 位运算
-- ============================================================

SELECT 5 & 3;                             -- 1  (AND)
SELECT 5 | 3;                             -- 7  (OR)
SELECT 5 # 3;                             -- 6  (XOR, PostgreSQL 用 #)
SELECT ~5;                                -- -6 (NOT)
SELECT 1 << 4;                            -- 16 (左移)
SELECT 16 >> 2;                           -- 4  (右移)

-- ============================================================
-- 7. 现代数学函数 (13+)
-- ============================================================

SELECT GCD(12, 18);                       -- 6  (最大公约数, 13+)
SELECT LCM(12, 18);                       -- 36 (最小公倍数, 13+)
SELECT MIN_SCALE(12.3400);                -- 2  (最小标度, 13+)
SELECT TRIM_SCALE(12.3400);               -- 12.34 (去尾零, 13+)
SELECT SCALE(123.456);                    -- 3  (小数位数)

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3, 9, 2);          -- 9
SELECT LEAST(1, 5, 3, 9, 2);             -- 1
-- 注意: 如果任一参数为 NULL，PostgreSQL 跳过 NULL（与 Oracle 不同）
-- Oracle 的 GREATEST(1, NULL, 3) = NULL; PostgreSQL 的 = 3

-- ============================================================
-- 8. 横向对比: 数学函数差异
-- ============================================================

-- 1. 幂运算符:
--   PostgreSQL: ^ (幂), # (XOR)
--   MySQL:      POW() (幂), ^ (XOR)
--   SQL Server: POWER() (幂), ^ (XOR)
--   注意: ^ 的语义完全相反!
--
-- 2. 平方根/立方根运算符:
--   PostgreSQL: |/ (平方根), ||/ (立方根) — 独有
--   其他:       均使用 SQRT() 函数，无立方根运算符
--
-- 3. 角度三角函数:
--   PostgreSQL: SIND, COSD, TAND 等 — 独有
--   其他:       需要手动 SIN(RADIANS(x))
--
-- 4. LOG 底数:
--   PostgreSQL: LOG(x) = log10(x)
--   MySQL:      LOG(x) = ln(x)
--   迁移时必须注意!

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- (1) 运算符语义的选择影响长期兼容性:
--     PostgreSQL 的 ^ = 幂运算在数学上直觉，但与 C/Java 语言的 XOR 冲突。
--     这种选择一旦确定就无法更改（breaking change）。
--     新引擎应仔细权衡，建议遵循 SQL 标准（POWER 函数）而非运算符。
--
-- (2) NUMERIC 类型的数学函数需要精确实现:
--     PostgreSQL 对 NUMERIC 类型使用任意精度算术（不转为 FLOAT）。
--     ROUND(1.005, 2) 在 PostgreSQL 中返回 1.01（精确），
--     但在某些语言的浮点实现中返回 1.00（IEEE 754 精度问题）。
--
-- (3) 随机数的实现:
--     RANDOM() 在每个 backend 独立维护状态，不需要全局锁。
--     SETSEED() 设置的种子是会话级的，不影响其他连接。

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- PostgreSQL 7.x:  基本数学函数, 弧度三角函数
-- PostgreSQL 7.2:  角度三角函数 (SIND, COSD 等)
-- PostgreSQL 12:   双曲函数 (SINH, COSH 等), LOG10
-- PostgreSQL 13:   GCD, LCM, MIN_SCALE, TRIM_SCALE
-- PostgreSQL 14:   DIV 函数（整除）
-- 注意: FACTORIAL(n) 和 n! 运算符在 14+ 已弃用
