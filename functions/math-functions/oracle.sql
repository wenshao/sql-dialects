-- Oracle: Math Functions
--
-- 参考资料:
--   [1] Oracle SQL Reference - Number Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Number-Functions.html

-- ============================================================
-- 基本数学函数
-- ============================================================
SELECT ABS(-42) FROM DUAL;                -- 42
SELECT CEIL(4.3) FROM DUAL;              -- 5
SELECT FLOOR(4.7) FROM DUAL;             -- 4
SELECT ROUND(3.14159, 2) FROM DUAL;      -- 3.14
SELECT ROUND(3.14159) FROM DUAL;          -- 3
SELECT TRUNC(3.14159, 2) FROM DUAL;      -- 3.14         (截断)
SELECT TRUNC(3.14159) FROM DUAL;          -- 3

-- ============================================================
-- 取模运算
-- ============================================================
SELECT MOD(17, 5) FROM DUAL;             -- 2
SELECT REMAINDER(17, 5) FROM DUAL;       -- 2            (IEEE 余数)
-- MOD 使用 FLOOR 除法，REMAINDER 使用 ROUND 除法

-- ============================================================
-- 幂、根、指数、对数
-- ============================================================
SELECT POWER(2, 10) FROM DUAL;           -- 1024
SELECT SQRT(144) FROM DUAL;              -- 12
SELECT EXP(1) FROM DUAL;                 -- 2.718281828...
SELECT LN(2.718281828) FROM DUAL;        -- ≈ 1.0        (自然对数)
SELECT LOG(10, 1000) FROM DUAL;          -- 3            (自定义底数)
-- 注意：Oracle LOG(base, x) 底数在前

-- ============================================================
-- 符号和常量
-- ============================================================
SELECT SIGN(-42) FROM DUAL;              -- -1
SELECT SIGN(0) FROM DUAL;                -- 0
SELECT SIGN(42) FROM DUAL;               -- 1
-- Oracle 没有 PI() 函数
SELECT ACOS(-1) FROM DUAL;               -- π (3.14159...)

-- ============================================================
-- 随机数 (DBMS_RANDOM)
-- ============================================================
SELECT DBMS_RANDOM.VALUE FROM DUAL;                     -- 0.0 到 1.0
SELECT DBMS_RANDOM.VALUE(1, 100) FROM DUAL;             -- 1 到 100
SELECT TRUNC(DBMS_RANDOM.VALUE(1, 101)) FROM DUAL;      -- 1 到 100 整数
SELECT DBMS_RANDOM.NORMAL FROM DUAL;                     -- 正态分布随机数

-- ============================================================
-- 三角函数（弧度）
-- ============================================================
SELECT SIN(0) FROM DUAL;                 -- 0
SELECT COS(0) FROM DUAL;                 -- 1
SELECT TAN(ACOS(-1)/4) FROM DUAL;        -- ≈ 1.0 (TAN(π/4))
SELECT ASIN(1) FROM DUAL;                -- π/2
SELECT ACOS(1) FROM DUAL;                -- 0
SELECT ATAN(1) FROM DUAL;                -- π/4
SELECT ATAN2(1, 1) FROM DUAL;            -- π/4

-- 双曲函数
SELECT SINH(1) FROM DUAL;                -- 1.1752...
SELECT COSH(1) FROM DUAL;                -- 1.5430...
SELECT TANH(1) FROM DUAL;                -- 0.7615...

-- ============================================================
-- GREATEST / LEAST
-- ============================================================
SELECT GREATEST(1, 5, 3, 9, 2) FROM DUAL; -- 9
SELECT LEAST(1, 5, 3, 9, 2) FROM DUAL;    -- 1
-- 注意：Oracle 中 NULL 参数不一定使结果为 NULL（行为因类型而异）

-- ============================================================
-- 位运算 (需要使用函数)                                -- 12c+
-- ============================================================
SELECT BITAND(5, 3) FROM DUAL;           -- 1            (AND)
-- OR, XOR, NOT 需要通过 BITAND 模拟或使用 UTL_RAW
-- Oracle 12c+ 在 PL/SQL 中支持更多位操作

-- ============================================================
-- 其他数学函数
-- ============================================================
SELECT WIDTH_BUCKET(42, 0, 100, 10) FROM DUAL;  -- 5     (直方图桶号)
SELECT NANVL(0/0, 0) FROM DUAL;                  -- 0     (NaN 替换)

-- 版本说明：
--   Oracle 全版本 : ABS, CEIL, FLOOR, ROUND, TRUNC, MOD, POWER, SQRT 等
--   Oracle 12c+   : BITAND 增强
-- 注意：Oracle 没有 PI() 函数，用 ACOS(-1)
-- 注意：Oracle LOG(base, x) 底数在前（其他数据库通常在后或不支持）
-- 注意：需要 FROM DUAL
-- 注意：REMAINDER 与 MOD 行为不同（IEEE 标准余数）
-- 限制：无 RAND() 或 RANDOM()（使用 DBMS_RANDOM）
-- 限制：位运算只有 BITAND（需模拟其他操作）
