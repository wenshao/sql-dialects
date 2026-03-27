-- KingbaseES (人大金仓): 数值类型
-- PostgreSQL compatible types.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 整数
-- SMALLINT:  2 字节
-- INTEGER:   4 字节
-- BIGINT:    8 字节

CREATE TABLE examples (
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);

-- 自增序列
-- SMALLSERIAL / SERIAL / BIGSERIAL
CREATE TABLE t (id BIGSERIAL PRIMARY KEY);

-- BOOLEAN
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

-- 浮点数
-- REAL:             4 字节
-- DOUBLE PRECISION: 8 字节

-- 定点数（精确）
-- NUMERIC(p,s) / DECIMAL(p,s)
CREATE TABLE prices (
    price    NUMERIC(10,2),
    rate     NUMERIC(5,4)
);

-- Oracle 兼容模式下的类型
-- NUMBER(p,s): Oracle 兼容

-- 注意事项：
-- 数值类型与 PostgreSQL 完全兼容
-- 不支持 UNSIGNED 类型
-- SERIAL 类型实际创建序列
-- Oracle 兼容模式下支持 NUMBER 类型
