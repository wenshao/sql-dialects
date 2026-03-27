-- MySQL: 数值类型
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Numeric Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/numeric-types.html
--   [2] MySQL 8.0 Reference Manual - Precision Math
--       https://dev.mysql.com/doc/refman/8.0/en/precision-math.html

-- 整数
-- TINYINT:   1 字节，-128 ~ 127（UNSIGNED: 0 ~ 255）
-- SMALLINT:  2 字节，-32768 ~ 32767
-- MEDIUMINT: 3 字节，-8388608 ~ 8388607
-- INT:       4 字节，-2^31 ~ 2^31-1
-- BIGINT:    8 字节，-2^63 ~ 2^63-1

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,           -- 无符号（MySQL 特有）
    flag       TINYINT(1)              -- 常用作布尔值（BOOL/BOOLEAN 是别名）
);

-- BOOL / BOOLEAN: TINYINT(1) 的别名
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 浮点数
-- FLOAT:  4 字节，约 7 位有效数字
-- DOUBLE: 8 字节，约 15 位有效数字
-- 注意：浮点数有精度损失问题

-- 定点数（精确）
-- DECIMAL(M,D) / NUMERIC(M,D): M 总位数，D 小数位数
CREATE TABLE prices (
    price    DECIMAL(10,2),            -- 精确到分
    rate     DECIMAL(5,4)              -- 如 1.2345
);

-- 8.0.17+: UNSIGNED 在浮点和定点类型上已废弃
-- 8.0.17+: FLOAT(M,D) / DOUBLE(M,D) 语法已废弃

-- BIT(M): 位字段，M 范围 1~64
CREATE TABLE t (flags BIT(8));

-- 自增
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);
-- 8.0+: 自增值持久化（重启后不回退）

-- 显示宽度（5.7 及之前，如 INT(11)）
-- 不影响存储范围，只影响 ZEROFILL 显示
-- 8.0.17+: 显示宽度已废弃
