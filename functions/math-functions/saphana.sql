-- SAP HANA: 数学函数
--
-- 参考资料:
--   [1] SAP HANA SQL Reference Guide - Numeric Functions
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/ba508d48dbb30d4ce10000000a1553f6.html
--   [2] SAP HANA SQL Reference Guide - Functions Overview
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/665e40e0d567417a9a3b35771b89e4be.html

-- ============================================================
-- 基础算术
-- ============================================================
SELECT ABS(-42) FROM DUMMY;                  -- 42           绝对值
SELECT CEIL(4.3) FROM DUMMY;                 -- 5            向上取整（注意：CEIL 而非 CEILING）
SELECT FLOOR(4.7) FROM DUMMY;                -- 4            向下取整
SELECT ROUND(3.14159, 2) FROM DUMMY;         -- 3.14         四舍五入到小数点后 2 位
SELECT ROUND(3.14159) FROM DUMMY;            -- 3            四舍五入到整数
SELECT ROUND(3.14159, 2, 'ROUND_HALF_UP') FROM DUMMY;   -- 3.14  指定舍入模式
SELECT ROUND(3.14159, 2, 'ROUND_HALF_DOWN') FROM DUMMY;  -- 3.14  向下舍入
SELECT MOD(17, 5) FROM DUMMY;                -- 2            取模
SELECT POWER(2, 10) FROM DUMMY;              -- 1024         幂运算
SELECT SQRT(144) FROM DUMMY;                 -- 12           平方根
SELECT SIGN(-42) FROM DUMMY;                 -- -1           符号函数
SELECT SIGN(0) FROM DUMMY;                   -- 0
SELECT SIGN(42) FROM DUMMY;                  -- 1

-- 注意：SAP HANA 使用 CEIL（不是 CEILING）
-- 注意：ROUND 支持第三参数指定舍入模式（ROUND_HALF_UP / ROUND_HALF_DOWN 等）
-- 注意：SAP HANA 需 FROM DUMMY（类似 Oracle 的 DUAL）
-- 注意：无 TRUNCATE/TRUNC 函数，可用 ROUND(x, d, 'ROUND_HALF_DOWN') 替代

-- ============================================================
-- 三角函数（弧度）
-- ============================================================
SELECT SIN(0) FROM DUMMY;                    -- 0            正弦
SELECT COS(0) FROM DUMMY;                    -- 1            余弦
SELECT TAN(0) FROM DUMMY;                    -- 0            正切
SELECT ASIN(1) FROM DUMMY;                   -- π/2          反正弦
SELECT ACOS(1) FROM DUMMY;                   -- 0            反余弦
SELECT ATAN(1) FROM DUMMY;                   -- π/4          反正切
SELECT ATAN2(1, 1) FROM DUMMY;               -- π/4          双参数反正切

-- 双曲函数
SELECT SINH(1) FROM DUMMY;                   -- 1.1752...    双曲正弦
SELECT COSH(1) FROM DUMMY;                   -- 1.5430...    双曲余弦
SELECT TANH(1) FROM DUMMY;                   -- 0.7615...    双曲正切

-- 弧度角度转换
SELECT DEGREES(ACOS(-1)) FROM DUMMY;         -- 180          弧度转角度
SELECT RADIANS(180) FROM DUMMY;              -- π            角度转弧度

-- ============================================================
-- 对数 / 指数
-- ============================================================
SELECT EXP(1) FROM DUMMY;                    -- 2.718281...  e 的指定次幂
SELECT LN(EXP(1)) FROM DUMMY;                -- ≈ 1.0        自然对数
SELECT LOG(10, 1000) FROM DUMMY;             -- 3            自定义底数对数

-- 注意：LOG(base, x) 底数在前、真数在后（同 Oracle/达梦）
-- 注意：无 LOG10 函数，可用 LOG(10, x) 替代
-- 注意：无 LOG2 函数，可用 LOG(2, x) 替代

-- ============================================================
-- 其他函数
-- ============================================================
-- 圆周率（无 PI() 函数）
SELECT ACOS(-1) FROM DUMMY;                  -- 3.141593     π 的近似值

-- 随机数
SELECT RAND() FROM DUMMY;                    -- 0~1 之间随机浮点数
SELECT RAND(42) FROM DUMMY;                  -- 可重复随机数（给定种子）
SELECT SECURE_RANDOM() FROM DUMMY;           -- 加密安全随机数（HANA 特有）

-- 安全数学函数
SELECT NDIV0(10, 0) FROM DUMMY;              -- 0            安全除法（除以零返回 0）
SELECT NDIV0(10, 2) FROM DUMMY;              -- 5            正常除法
SELECT NVE(42) FROM DUMMY;                   -- 42           NULL 值安全转换

-- GREATEST / LEAST
SELECT GREATEST(1, 5, 3, 9, 2) FROM DUMMY;  -- 9            取最大值
SELECT LEAST(1, 5, 3, 9, 2) FROM DUMMY;     -- 1            取最小值

-- 位运算
SELECT BITAND(5, 3) FROM DUMMY;              -- 1            按位与
SELECT BITOR(5, 3) FROM DUMMY;               -- 7            按位或
SELECT BITXOR(5, 3) FROM DUMMY;              -- 6            按位异或
SELECT BITNOT(5) FROM DUMMY;                 -- -6           按位取反

-- 进制转换
SELECT HEXTOBIN('FF') FROM DUMMY;            -- 二进制值     十六进制转二进制
SELECT BINTOHEX(X'FF') FROM DUMMY;           -- 'FF'         二进制转十六进制

-- 版本说明：
--   SAP HANA 1.0 SPS12+ : 基本数学函数
--   SAP HANA 2.0 SPS00+ : 完整数学函数，SECURE_RANDOM
--   SAP HANA 2.0 SPS05+ : 增强 ROUND 舍入模式
-- 注意：SAP HANA 需要 FROM DUMMY（类似 Oracle 的 DUAL）
-- 注意：LOG(base, x) 参数顺序：底数在前，真数在后
-- 注意：无 PI() 函数，使用 ACOS(-1) 替代（≈ 3.14159265358979）
-- 注意：NDIV0 是 HANA 特有的安全除法函数，避免除以零错误
-- 注意：SECURE_RANDOM 生成加密安全的随机数
-- 注意：ROUND 支持舍入模式字符串参数（HANA 特有扩展）
-- 限制：无 CBRT、LOG10、LOG2 函数
-- 限制：无 TRUNCATE/TRUNC 函数
