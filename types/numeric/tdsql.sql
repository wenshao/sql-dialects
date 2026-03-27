-- TDSQL: 数值类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 整数
-- TINYINT:   1 字节
-- SMALLINT:  2 字节
-- MEDIUMINT: 3 字节
-- INT:       4 字节
-- BIGINT:    8 字节

CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)
);

-- BOOL / BOOLEAN
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 浮点数
-- FLOAT / DOUBLE

-- 定点数
-- DECIMAL(M,D) / NUMERIC(M,D)
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     DECIMAL(5,4)
);

-- BIT(M)
CREATE TABLE t (flags BIT(8));

-- 自增
CREATE TABLE t (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);

-- 注意事项：
-- 数值类型与 MySQL 完全兼容
-- shardkey 列推荐使用 INT 或 BIGINT
-- AUTO_INCREMENT 全局唯一但不连续
-- BIT 类型不能作为 shardkey
