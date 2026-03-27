-- Vertica: 数学函数
--
-- 参考资料:
--   [1] Vertica Documentation - Mathematical Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Mathematical/MathFunctions.htm
--   [2] Vertica Documentation - Operators
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/LanguageElements/Operators/operator.htm

-- ============================================================
-- 基础算术
-- ============================================================
SELECT ABS(-42);                             -- 42           绝对值
SELECT CEIL(4.3);                            -- 5            向上取整
SELECT CEILING(4.3);                         -- 5            向上取整（CEIL 同义）
SELECT FLOOR(4.7);                           -- 4            向下取整
SELECT ROUND(3.14159, 2);                    -- 3.14         四舍五入
SELECT ROUND(3.14159);                       -- 3            四舍五入到整数
SELECT TRUNC(3.14159, 2);                    -- 3.14         截断（TRUNCATE 同义）
SELECT TRUNCATE(3.14159, 2);                 -- 3.14         截断
SELECT MOD(17, 5);                           -- 2            取模函数
SELECT 17 % 5;                               -- 2            取模运算符
SELECT POWER(2, 10);                         -- 1024         幂运算
SELECT POW(2, 10);                           -- 1024         幂运算（POWER 缩写）
SELECT SQRT(144);                            -- 12           平方根
SELECT CBRT(27);                             -- 3            立方根
SELECT SIGN(-42);                            -- -1           符号函数
SELECT SIGN(0);                              -- 0
SELECT SIGN(42);                             -- 1

-- 注意：Vertica 同时支持 TRUNC 和 TRUNCATE
-- 注意：支持 CBRT（立方根），与 PostgreSQL 一致

-- ============================================================
-- 三角函数（弧度）
-- ============================================================
SELECT SIN(0);                               -- 0            正弦
SELECT COS(0);                               -- 1            余弦
SELECT TAN(0);                               -- 0            正切
SELECT ASIN(1);                              -- π/2          反正弦
SELECT ACOS(1);                              -- 0            反余弦
SELECT ATAN(1);                              -- π/4          反正切
SELECT ATAN2(1, 1);                          -- π/4          双参数反正切

-- 双曲函数
SELECT SINH(1);                              -- 1.1752...    双曲正弦
SELECT COSH(1);                              -- 1.5430...    双曲余弦
SELECT TANH(1);                              -- 0.7615...    双曲正切

-- 弧度角度转换
SELECT DEGREES(PI());                        -- 180          弧度转角度
SELECT RADIANS(180);                         -- π            角度转弧度

-- ============================================================
-- 对数 / 指数
-- ============================================================
SELECT EXP(1);                               -- 2.718281...  e 的指定次幂
SELECT LN(EXP(1));                           -- ≈ 1.0        自然对数
SELECT LOG(100);                             -- 2            以 10 为底的对数（注意！）
SELECT LOG10(1000);                          -- 3            以 10 为底的对数

-- 注意：Vertica 中 LOG(x) 以 10 为底（同 PostgreSQL），不同于 MySQL 以 e 为底
-- 注意：无 LOG(x, base) 自定义底数形式，可用 LN(x)/LN(base) 手动计算
-- 注意：无 LOG2 函数，可用 LOG(x)/LOG(2) 替代

-- ============================================================
-- 其他函数
-- ============================================================
SELECT PI();                                 -- 3.141593     圆周率常量

-- 随机数
SELECT RANDOM();                             -- 0~1 之间随机浮点数
SELECT RANDOMINT(100);                       -- 0~99 随机整数（Vertica 特有）
SELECT HASH('', 42);                         -- 哈希值（也可用于生成伪随机数）

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3, 9, 2);             -- 9            取最大值
SELECT LEAST(1, 5, 3, 9, 2);                -- 1            取最小值

-- 位运算符
SELECT 5 & 3;                               -- 1            按位与 (AND)
SELECT 5 | 3;                               -- 7            按位或 (OR)
SELECT 5 # 3;                               -- 6            按位异或 (XOR，# 符号)
SELECT ~5;                                   -- -6           按位取反 (NOT)

-- 版本说明：
--   Vertica 9.x+ : 完整数学函数支持
--   Vertica 10.x+: 性能优化，支持向量化执行
--   Vertica 11.x+: 增强随机函数
-- 注意：# 是 XOR 运算符（不同于 MySQL 的 ^）
-- 注意：LOG(x) 以 10 为底（与 PostgreSQL 一致）
-- 注意：RANDOM() 无参数（不支持种子），如需可重复随机可用 SET SEED
-- 注意：RANDOMINT(n) 返回 0 到 n-1 的随机整数，是 Vertica 特有函数
