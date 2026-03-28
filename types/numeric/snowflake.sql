-- Snowflake: 数值类型
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Numeric Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types-numeric

-- ============================================================
-- 1. 类型概述
-- ============================================================

-- NUMBER(p, s): 通用数值类型，p 精度(最大38)，s 小数位
-- NUMBER:       默认 NUMBER(38, 0)，即 38 位整数
-- INT/INTEGER/BIGINT/SMALLINT/TINYINT/BYTEINT: 全部是 NUMBER(38,0) 的别名
-- FLOAT/FLOAT4/FLOAT8/DOUBLE/REAL: 全部是 8 字节 IEEE 754 双精度
-- DECIMAL/NUMERIC: NUMBER 的别名
-- BOOLEAN: TRUE / FALSE / NULL

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 所有整数别名底层相同
CREATE TABLE examples (
    id        INTEGER,         -- NUMBER(38, 0)
    small_val SMALLINT,        -- NUMBER(38, 0)，与 INTEGER 完全相同!
    big_val   BIGINT           -- NUMBER(38, 0)，与 INTEGER 完全相同!
);
-- Snowflake 不区分 TINYINT/SMALLINT/INT/BIGINT 的存储大小。
-- 所有整数都是 NUMBER(38, 0)，最大 38 位十进制数。
-- 对比:
--   MySQL/PostgreSQL: SMALLINT(2B) / INT(4B) / BIGINT(8B)，存储大小不同
--   Oracle:           NUMBER 也是统一类型（与 Snowflake 最一致）
--   BigQuery:         INT64（统一 8 字节整数）
--
-- 对引擎开发者的启示:
--   统一整数类型简化了实现（无需多种整数宽度），
--   但用户无法通过类型约束值的范围。
--   Oracle 和 Snowflake 选择了简化，MySQL/PG 选择了精细控制。
--   列存引擎可以根据实际数据自动选择最优编码（字典/RLE/位压缩），
--   不需要用户通过类型指定存储大小。

-- 2.2 无真正的单精度浮点
-- FLOAT4 在 Snowflake 中也是双精度（8 字节 IEEE 754）。
-- 不存在单精度浮点的节省存储优势。
CREATE TABLE measurements (
    value  FLOAT,                 -- 8 字节双精度
    result DOUBLE PRECISION       -- 同 FLOAT
);

-- ============================================================
-- 3. 定点数
-- ============================================================

CREATE TABLE prices (
    price NUMBER(10, 2),          -- 10 位精度，2 位小数
    rate  DECIMAL(5, 4)           -- NUMBER(5, 4) 的别名
);
-- 对比 FLOAT: NUMBER(10,2) 精确存储（无浮点误差），适合金融计算
-- 对比 MySQL: DECIMAL(p,s) 语义一致

-- ============================================================
-- 4. 布尔类型
-- ============================================================

CREATE TABLE flags (active BOOLEAN DEFAULT TRUE);
-- 值: TRUE / FALSE / NULL
-- 对比:
--   PostgreSQL: BOOLEAN（相同）
--   MySQL:      BOOLEAN = TINYINT(1)（不是真正的布尔）
--   Oracle:     无原生 BOOLEAN（用 NUMBER(1) 或 CHAR(1) 模拟）

-- ============================================================
-- 5. 自增
-- ============================================================

CREATE TABLE t (
    id  INTEGER AUTOINCREMENT,           -- Snowflake 风格
    id2 INTEGER IDENTITY                 -- SQL 标准风格
);

CREATE SEQUENCE seq1;
CREATE TABLE t2 (id INTEGER DEFAULT seq1.NEXTVAL);

-- ============================================================
-- 6. 类型转换
-- ============================================================

SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;
SELECT TRY_CAST('abc' AS INTEGER);       -- NULL（安全转换）
SELECT TO_NUMBER('123.45', 10, 2);

-- ============================================================
-- 7. 安全数学函数
-- ============================================================

SELECT DIV0(10, 0);           -- 0（安全除法）
SELECT DIV0NULL(10, 0);       -- NULL（安全除法）
-- 对比: 传统 SQL 除以零报错，Snowflake 提供安全替代

-- ============================================================
-- 横向对比: 数值类型
-- ============================================================
-- 特性           | Snowflake       | BigQuery    | PostgreSQL    | MySQL
-- 整数类型       | 统一NUMBER(38,0)| INT64       | 多种(2/4/8B)  | 多种(1-8B)
-- 最大精度       | 38 位           | 38 位       | 无限(NUMERIC) | 65 位
-- 浮点           | 只有双精度      | FLOAT64     | real/double   | FLOAT/DOUBLE
-- BOOLEAN        | 原生            | 原生        | 原生          | TINYINT(1)
-- UNSIGNED       | 不支持          | 不支持      | 不支持        | 支持
-- 安全除法       | DIV0            | IEEE_DIVIDE | 不支持        | 不支持
-- 自增           | AUTOINCREMENT   | 不支持      | SERIAL/IDENT  | AUTO_INCREMENT
