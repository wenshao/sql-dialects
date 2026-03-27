-- TimescaleDB: 数值类型
--
-- 参考资料:
--   [1] TimescaleDB API Reference
--       https://docs.timescale.com/api/latest/
--   [2] TimescaleDB Hyperfunctions
--       https://docs.timescale.com/api/latest/hyperfunctions/

-- TimescaleDB 继承 PostgreSQL 全部数值类型

-- 整数
-- SMALLINT: 2 字节，-32768 ~ 32767
-- INTEGER / INT: 4 字节，-2^31 ~ 2^31-1
-- BIGINT: 8 字节，-2^63 ~ 2^63-1

CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INT NOT NULL,
    reading_id  BIGINT,
    status_code SMALLINT
);

-- 序列 / 自增
CREATE TABLE devices (
    id       SERIAL PRIMARY KEY,              -- 4 字节自增
    name     TEXT
);
CREATE TABLE events (
    id       BIGSERIAL PRIMARY KEY,           -- 8 字节自增
    data     TEXT
);

-- 浮点数
-- REAL / FLOAT4: 4 字节，6 位精度
-- DOUBLE PRECISION / FLOAT8: 8 字节，15 位精度
CREATE TABLE readings (
    temperature REAL,
    pressure    DOUBLE PRECISION
);

-- 定点数
-- NUMERIC(p,s) / DECIMAL(p,s): 精确数值
CREATE TABLE prices (
    amount NUMERIC(10,2),
    tax    DECIMAL(5,4)
);

-- 布尔
CREATE TABLE flags (active BOOLEAN DEFAULT TRUE);

-- 类型转换
SELECT CAST('123' AS INTEGER);
SELECT '123'::INT;
SELECT CAST(3.14 AS NUMERIC(10,2));

-- 特殊数值
SELECT 'NaN'::FLOAT;
SELECT 'Infinity'::FLOAT;
SELECT '-Infinity'::FLOAT;

-- 数学函数
SELECT ABS(-5), MOD(10, 3), ROUND(3.14159, 2);
SELECT CEIL(3.14), FLOOR(3.14), TRUNC(3.14159, 2);
SELECT POWER(2, 10), SQRT(144), LOG(100);

-- 注意：完全兼容 PostgreSQL 的数值类型
-- 注意：SERIAL/BIGSERIAL 是自增序列的简写
-- 注意：时序数据常用 DOUBLE PRECISION 存储测量值
-- 注意：金融数据推荐使用 NUMERIC 精确类型
