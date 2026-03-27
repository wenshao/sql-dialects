-- Greenplum: 数值类型
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- 整数
-- SMALLINT / INT2:    2 字节，-32768 ~ 32767
-- INTEGER / INT / INT4: 4 字节，-2^31 ~ 2^31-1
-- BIGINT / INT8:      8 字节，-2^63 ~ 2^63-1
-- SERIAL:             4 字节自增整数
-- BIGSERIAL:          8 字节自增整数

CREATE TABLE examples (
    id         BIGSERIAL PRIMARY KEY,
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
)
DISTRIBUTED BY (id);

-- 浮点数
-- REAL / FLOAT4:      4 字节，6 位精度
-- DOUBLE PRECISION / FLOAT8: 8 字节，15 位精度
-- FLOAT(n):           n <= 24 用 REAL，n >= 25 用 DOUBLE PRECISION

-- 定点数
-- NUMERIC(P, S) / DECIMAL(P, S): 精确，P 最大 1000
-- MONEY: 货币类型
CREATE TABLE prices (
    price      NUMERIC(10, 2),            -- 精确到分
    value      DOUBLE PRECISION,          -- 浮点数
    amount     MONEY                      -- 货币（$1,000.00 格式）
)
DISTRIBUTED RANDOMLY;

-- 布尔
-- BOOLEAN / BOOL: TRUE / FALSE / NULL
CREATE TABLE t (
    active BOOLEAN DEFAULT TRUE
)
DISTRIBUTED RANDOMLY;

-- 序列（自增）
CREATE SEQUENCE user_id_seq START 1 INCREMENT 1;
-- 使用序列
CREATE TABLE users (
    id BIGINT DEFAULT nextval('user_id_seq') PRIMARY KEY,
    name VARCHAR(64)
)
DISTRIBUTED BY (id);

-- 特殊数值
SELECT 'NaN'::NUMERIC;                   -- Not a Number
SELECT 'Infinity'::FLOAT;               -- 正无穷
SELECT '-Infinity'::FLOAT;              -- 负无穷

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                    -- PostgreSQL 简写
SELECT 123::NUMERIC(10,2);

-- 数学运算
SELECT 5 / 2;                            -- 整数除法 = 2
SELECT 5.0 / 2;                          -- 浮点除法 = 2.5
SELECT 5 % 2;                            -- 取模 = 1
SELECT 2 ^ 10;                           -- 幂运算 = 1024
SELECT |/ 144;                           -- 平方根 = 12

-- 注意：Greenplum 兼容 PostgreSQL 数值类型
-- 注意：SERIAL/BIGSERIAL 在分布式环境下不保证连续
-- 注意：NUMERIC 精度最高 1000 位
-- 注意：MONEY 类型受 lc_monetary 设置影响
