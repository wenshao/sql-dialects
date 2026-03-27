-- SQL Server: 数值类型
--
-- 参考资料:
--   [1] SQL Server T-SQL - Numeric Data Types
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/int-bigint-smallint-and-tinyint-transact-sql
--   [2] SQL Server T-SQL - decimal and numeric
--       https://learn.microsoft.com/en-us/sql/t-sql/data-types/decimal-and-numeric-transact-sql

-- 整数
-- TINYINT:  1 字节，0 ~ 255（无符号！）
-- SMALLINT: 2 字节，-32768 ~ 32767
-- INT:      4 字节，-2^31 ~ 2^31-1
-- BIGINT:   8 字节，-2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val   TINYINT,                -- 注意：TINYINT 是无符号的
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT
);

-- 浮点数
-- REAL / FLOAT(24):            4 字节，约 7 位有效数字
-- FLOAT / FLOAT(53):           8 字节，约 15 位有效数字
-- FLOAT(n): n 为二进制精度，1~24 映射为 4 字节，25~53 映射为 8 字节

-- 定点数（精确）
-- DECIMAL(p,s) / NUMERIC(p,s): p 最大 38
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     NUMERIC(5,4)
);

-- 货币类型
-- MONEY:      8 字节，精确到万分之一
-- SMALLMONEY: 4 字节
CREATE TABLE t (amount MONEY);
-- 注意：MONEY 运算有精度陷阱，推荐用 DECIMAL

-- 布尔：BIT 类型
CREATE TABLE t (active BIT DEFAULT 1);  -- 值: 0, 1, NULL

-- 自增
CREATE TABLE t (id BIGINT IDENTITY(1,1) PRIMARY KEY);
-- IDENTITY(seed, increment)

-- 2012+: SEQUENCE（类似 Oracle）
CREATE SEQUENCE user_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR user_seq;

-- 注意：除了 TINYINT，其他整数都没有 UNSIGNED 选项
-- 注意：BIT 列不能作为自增列
