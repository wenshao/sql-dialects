-- openGauss/GaussDB: 数值类型
-- PostgreSQL compatible with extensions.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- 整数
-- SMALLINT:  2 字节，-32768 ~ 32767
-- INTEGER:   4 字节，-2^31 ~ 2^31-1
-- BIGINT:    8 字节，-2^63 ~ 2^63-1
-- TINYINT:   1 字节（openGauss 扩展）

CREATE TABLE examples (
    tiny_val   TINYINT,              -- openGauss 扩展
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);

-- 自增序列
-- SMALLSERIAL: 2 字节自增
-- SERIAL:      4 字节自增
-- BIGSERIAL:   8 字节自增
CREATE TABLE t (id BIGSERIAL PRIMARY KEY);

-- BOOLEAN
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 浮点数
-- REAL:             4 字节，约 6 位有效数字
-- DOUBLE PRECISION: 8 字节，约 15 位有效数字
-- FLOAT4 / FLOAT8:  同上

-- 定点数（精确）
-- NUMERIC(p,s) / DECIMAL(p,s)
CREATE TABLE prices (
    price    NUMERIC(10,2),
    rate     NUMERIC(5,4)
);

-- NUMBER(p,s): Oracle 兼容
CREATE TABLE oracle_compat (
    amount   NUMBER(10,2)
);

-- 注意事项：
-- 支持 TINYINT（openGauss 扩展，PostgreSQL 不支持）
-- 支持 NUMBER 类型（Oracle 兼容）
-- 不支持 UNSIGNED 类型
-- SERIAL 类型实际上创建一个序列
-- 列存储表对数值类型有更好的压缩效果
