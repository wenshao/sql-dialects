-- 达梦 (DM): 数学函数
--
-- 参考资料:
--   [1] 达梦数据库 SQL 语言参考手册 - 数学函数
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/practice/function/math.html
--   [2] 达梦数据库 SQL 语言参考手册 - 内置函数
--       https://eco.dameng.com/document/dm/zh-cn/pm/sql-reference-function.html

-- ============================================================
-- 基础算术
-- ============================================================
SELECT ABS(-42) FROM DUAL;                   -- 42           绝对值
SELECT CEIL(4.3) FROM DUAL;                  -- 5            向上取整
SELECT FLOOR(4.7) FROM DUAL;                 -- 4            向下取整
SELECT ROUND(3.14159, 2) FROM DUAL;          -- 3.14         四舍五入到小数点后 2 位
SELECT ROUND(3.14159) FROM DUAL;             -- 3            四舍五入到整数
SELECT TRUNC(3.14159, 2) FROM DUAL;          -- 3.14         截断（注意：TRUNC 而非 TRUNCATE）
SELECT TRUNC(3.14159) FROM DUAL;             -- 3            截断到整数
SELECT MOD(17, 5) FROM DUAL;                 -- 2            取模
SELECT POWER(2, 10) FROM DUAL;               -- 1024         幂运算
SELECT SQRT(144) FROM DUAL;                  -- 12           平方根
SELECT SIGN(-42) FROM DUAL;                  -- -1           符号函数
SELECT SIGN(0) FROM DUAL;                    -- 0
SELECT SIGN(42) FROM DUAL;                   -- 1

-- 注意：达梦兼容 Oracle 数学函数语法，大多数函数需要 FROM DUAL
-- 注意：TRUNC（不是 TRUNCATE），与 Oracle 一致
-- 注意：无 CBRT（立方根）函数，可用 POWER(x, 1.0/3) 替代

-- ============================================================
-- 三角函数（弧度）
-- ============================================================
SELECT SIN(0) FROM DUAL;                     -- 0            正弦
SELECT COS(0) FROM DUAL;                     -- 1            余弦
SELECT TAN(0) FROM DUAL;                     -- 0            正切
SELECT ASIN(1) FROM DUAL;                    -- π/2          反正弦
SELECT ACOS(1) FROM DUAL;                    -- 0            反余弦
SELECT ATAN(1) FROM DUAL;                    -- π/4          反正切
SELECT ATAN2(1, 1) FROM DUAL;                -- π/4          双参数反正切

-- 双曲函数
SELECT SINH(1) FROM DUAL;                    -- 1.1752...    双曲正弦
SELECT COSH(1) FROM DUAL;                    -- 1.5430...    双曲余弦
SELECT TANH(1) FROM DUAL;                    -- 0.7615...    双曲正切

-- 弧度角度转换
SELECT DEGREES(ACOS(-1)) FROM DUAL;          -- 180          弧度转角度
SELECT RADIANS(180) FROM DUAL;               -- π            角度转弧度

-- 注意：达梦无 PI() 函数，可使用 ACOS(-1) 获取 π 值

-- ============================================================
-- 对数 / 指数
-- ============================================================
SELECT EXP(1) FROM DUAL;                     -- 2.718281...  e 的指定次幂
SELECT LN(EXP(1)) FROM DUAL;                 -- ≈ 1.0        自然对数
SELECT LOG(10, 1000) FROM DUAL;              -- 3            自定义底数对数

-- 注意：LOG(base, x) 底数在前、真数在后（与 Oracle 一致）
--       区别于 MySQL 的 LOG(x) 以 e 为底、LOG(base, x) 底数在前
-- 注意：无 LOG10 函数，可用 LOG(10, x) 替代
-- 注意：无 LOG2 函数，可用 LOG(2, x) 替代

-- ============================================================
-- 其他函数
-- ============================================================
-- 圆周率（无 PI() 函数）
SELECT ACOS(-1) FROM DUAL;                   -- 3.141593     π 的近似值

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3, 9, 2) FROM DUAL;   -- 9            取最大值
SELECT LEAST(1, 5, 3, 9, 2) FROM DUAL;      -- 1            取最小值

-- 位运算
SELECT BITAND(5, 3) FROM DUAL;               -- 1            按位与

-- 宽裕兼容函数
SELECT REMAINDER(17, 5) FROM DUAL;           -- 2            余数（类似 MOD）
SELECT WIDTH_BUCKET(90, 0, 100, 10) FROM DUAL;  -- 9         等宽分桶

-- 版本说明：
--   DM7 : 基本数学函数，兼容 Oracle
--   DM8 : 增强函数集，性能优化
-- 注意：达梦数学函数高度兼容 Oracle，语法和参数顺序一致
-- 注意：需要 FROM DUAL（单行查询必须含 FROM 子句）
-- 注意：LOG(base, x) 参数顺序：底数在前，真数在后
-- 注意：无 PI() 函数，使用 ACOS(-1) 替代（≈ 3.14159265358979）
-- 限制：无 CBRT、LOG10、LOG2 函数
-- 限制：位运算仅支持 BITAND（无 BITOR/BITXOR/BITNOT 函数）
