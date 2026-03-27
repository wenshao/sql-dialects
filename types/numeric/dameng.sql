-- DamengDB (达梦): 数值类型
-- Oracle compatible types.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- 整数
-- TINYINT:   1 字节，0 ~ 255
-- SMALLINT:  2 字节
-- INT:       4 字节
-- BIGINT:    8 字节
-- NUMBER(p): Oracle 兼容的整数

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    oracle_int NUMBER(10)            -- Oracle 兼容
);

-- 浮点数
-- FLOAT:          单精度
-- DOUBLE:         双精度
-- REAL:           同 FLOAT
-- DOUBLE PRECISION: 同 DOUBLE
-- NUMBER / NUMERIC: Oracle 兼容的任意精度

-- 定点数（精确）
-- DECIMAL(M,D) / NUMERIC(M,D) / NUMBER(M,D)
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     NUMBER(5,4),            -- Oracle 兼容
    amount   NUMERIC(10,2)
);

-- 布尔值
-- BIT: 0 或 1
CREATE TABLE t (active BIT DEFAULT 1);

-- 自增（IDENTITY）
CREATE TABLE t (id INT IDENTITY(1,1) PRIMARY KEY);

-- 序列（Oracle 风格）
CREATE SEQUENCE seq_id START WITH 1 INCREMENT BY 1;

-- 注意事项：
-- NUMBER 类型与 Oracle 兼容
-- 支持 IDENTITY 列（类似 SQL Server）
-- 支持序列（Oracle 风格）
-- TINYINT 范围是 0~255（无符号）
-- 不支持 UNSIGNED 关键字
-- MySQL 兼容模式下支持 AUTO_INCREMENT
