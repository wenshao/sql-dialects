-- SQL Server: 数值类型
--
-- 参考资料:
--   [1] SQL Server T-SQL - Numeric Data Types
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/int-bigint-smallint-and-tinyint-transact-sql

-- ============================================================
-- 1. 整数类型
-- ============================================================

-- TINYINT:  1 字节, 0 ~ 255（无符号！SQL Server 唯一的无符号整数）
-- SMALLINT: 2 字节, -32768 ~ 32767
-- INT:      4 字节, -2^31 ~ 2^31-1
-- BIGINT:   8 字节, -2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val  TINYINT,   -- 注意: TINYINT 是无符号的（0-255）
    small_val SMALLINT,
    int_val   INT,
    big_val   BIGINT
);

-- 设计分析（对引擎开发者）:
--   SQL Server 的 TINYINT 是无符号的（0-255），这与其他整数类型不同。
--   其他整数类型（SMALLINT/INT/BIGINT）都是有符号的，且没有 UNSIGNED 变体。
--
-- 横向对比:
--   MySQL:      所有整数类型都有 UNSIGNED 变体（BIGINT UNSIGNED 0 ~ 2^64-1）
--   PostgreSQL: 无 UNSIGNED（TINYINT 也不支持）
--   Oracle:     无整数类型，只有 NUMBER(p,s)
--
-- 对引擎开发者的启示:
--   UNSIGNED 整数在存储优化中有价值（同样字节数表示更大范围），
--   但增加了类型系统复杂度（运算时需要处理有符号/无符号混合）。
--   PostgreSQL 选择不支持 UNSIGNED 是为了简化类型系统——这是合理的取舍。

-- ============================================================
-- 2. 浮点数
-- ============================================================

-- REAL / FLOAT(24):  4 字节, 约 7 位有效数字（单精度）
-- FLOAT / FLOAT(53): 8 字节, 约 15 位有效数字（双精度）
-- FLOAT(n): n 为二进制位精度，1-24 → 4 字节，25-53 → 8 字节

-- 浮点数的经典精度问题:
SELECT CAST(0.1 + 0.2 AS FLOAT);  -- 0.30000000000000004（不是 0.3）
-- 财务计算永远不要用 FLOAT/REAL

-- ============================================================
-- 3. 定点数（精确小数）
-- ============================================================

-- DECIMAL(p,s) / NUMERIC(p,s): p 最大 38, s 最大 p
-- DECIMAL 和 NUMERIC 在 SQL Server 中完全相同（别名）
CREATE TABLE prices (
    price DECIMAL(10,2),    -- 10 位总精度, 2 位小数
    rate  NUMERIC(5,4)      -- 5 位总精度, 4 位小数
);

-- 存储大小取决于精度:
-- p 1-9:   5 字节
-- p 10-19: 9 字节
-- p 20-28: 13 字节
-- p 29-38: 17 字节

-- ============================================================
-- 4. MONEY / SMALLMONEY: SQL Server 独有的货币类型
-- ============================================================

CREATE TABLE transactions (amount MONEY);

-- MONEY:      8 字节, -922,337,203,685,477.5808 ~ 922,337,203,685,477.5807
-- SMALLMONEY: 4 字节, -214,748.3648 ~ 214,748.3647
-- 固定 4 位小数精度

-- 设计分析（对引擎开发者）:
--   MONEY 类型看似方便，但有严重的精度陷阱:
SELECT CAST(1 AS MONEY) / 3 * 3;  -- 0.9999（不是 1.0000）
--   MONEY 的除法只保留 4 位小数后截断，然后再乘法——累积误差。
--   DECIMAL(19,4) 的除法保留中间结果的完整精度。
--
--   大部分 SQL Server 专家建议: 不要使用 MONEY，用 DECIMAL 替代。
--
-- 横向对比:
--   PostgreSQL: money 类型存在但不推荐使用（类似的精度问题）
--   MySQL:      无 MONEY 类型
--   Oracle:     无 MONEY 类型（使用 NUMBER）

-- ============================================================
-- 5. BIT: SQL Server 的布尔类型
-- ============================================================

CREATE TABLE flags (active BIT DEFAULT 1);  -- 值: 0, 1, NULL

-- BIT 不是真正的布尔类型:
--   不能在 WHERE 中直接使用: WHERE active（错误，需要 WHERE active = 1）
--   不支持 TRUE/FALSE 关键字（2016+ 仍然不支持）
--
-- 横向对比:
--   PostgreSQL: BOOLEAN 类型, 支持 TRUE/FALSE, WHERE active 直接可用
--   MySQL:      BOOLEAN 是 TINYINT(1) 的别名, 支持 TRUE/FALSE
--   Oracle:     无布尔类型（表列中）, PL/SQL 有 BOOLEAN
--
-- 对引擎开发者的启示:
--   缺少真正的 BOOLEAN 类型是 SQL Server 的设计遗憾。
--   BIT 的 NULL 语义（三值: 0/1/NULL）增加了复杂性。
--   现代引擎应支持标准 BOOLEAN 类型和 TRUE/FALSE 字面量。

-- 存储优化: 同一表中的多个 BIT 列共享字节
-- 1 个 BIT = 1 字节, 2-8 个 BIT = 1 字节, 9-16 个 BIT = 2 字节

-- ============================================================
-- 6. 自增（IDENTITY 和 SEQUENCE）
-- ============================================================

CREATE TABLE t (id BIGINT IDENTITY(1,1) PRIMARY KEY);
-- IDENTITY(seed, increment)

-- 2012+: SEQUENCE
CREATE SEQUENCE user_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR user_seq;

-- ============================================================
-- 7. 数值类型选择指南
-- ============================================================

-- 整数 ID:          BIGINT IDENTITY（推荐）或 INT IDENTITY（小表）
-- 金额/货币:        DECIMAL(19,4)（不要用 MONEY）
-- 百分比:           DECIMAL(5,4)（0.0000 ~ 1.0000）
-- 科学计算:         FLOAT（接受近似）
-- 布尔标志:         BIT
-- 极小范围（0-255）: TINYINT
