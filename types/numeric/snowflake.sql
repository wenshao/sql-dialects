-- Snowflake: 数值类型
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Numeric Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types-numeric
--   [2] Snowflake SQL Reference - Numeric Functions
--       https://docs.snowflake.com/en/sql-reference/functions-numeric

-- NUMBER(p, s): 通用数值类型（最大精度 38）
-- NUMBER: 默认 NUMBER(38, 0)，即整数
-- NUMBER(p, s): p 总位数，s 小数位
-- INT / INTEGER / BIGINT / SMALLINT / TINYINT / BYTEINT: 均为 NUMBER(38, 0) 的别名

CREATE TABLE examples (
    id         INTEGER,                   -- NUMBER(38, 0) 的别名
    small_val  SMALLINT,                  -- NUMBER(38, 0) 的别名
    big_val    BIGINT                     -- NUMBER(38, 0) 的别名
);

-- 注意：所有整数别名底层都是 NUMBER(38, 0)，无存储大小区别

-- 定点数
-- DECIMAL / NUMERIC: NUMBER 的别名
CREATE TABLE prices (
    price      NUMBER(10, 2),             -- 精确到分
    rate       DECIMAL(5, 4)              -- NUMBER(5, 4) 的别名
);

-- 浮点数
-- FLOAT / FLOAT4 / FLOAT8: 8 字节 IEEE 754 双精度
-- DOUBLE / DOUBLE PRECISION / REAL: FLOAT 的别名
CREATE TABLE measurements (
    value      FLOAT,                     -- IEEE 754 双精度
    result     DOUBLE PRECISION           -- 同 FLOAT
);

-- 注意：Snowflake 没有真正的单精度浮点，FLOAT4 也是双精度

-- 布尔
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
-- 值: TRUE / FALSE / NULL

-- 自增
CREATE TABLE t (
    id INTEGER AUTOINCREMENT,             -- Snowflake 风格
    id2 INTEGER IDENTITY                  -- SQL 标准风格
);

-- 序列
CREATE SEQUENCE seq1;
CREATE TABLE t (id INTEGER DEFAULT seq1.NEXTVAL);

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT TRY_CAST('abc' AS INTEGER);        -- 安全转换
SELECT '123'::INTEGER;                    -- :: 转换语法
SELECT TO_NUMBER('123.45', 10, 2);        -- 转为 NUMBER(10,2)

-- 注意：没有 UNSIGNED 类型
-- 注意：没有 BIT 类型
-- 注意：NUMBER 最大精度 38 位
