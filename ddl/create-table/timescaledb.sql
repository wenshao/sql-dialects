-- TimescaleDB: CREATE TABLE
--
-- 参考资料:
--   [1] TimescaleDB API Reference
--       https://docs.timescale.com/api/latest/
--   [2] TimescaleDB Hyperfunctions
--       https://docs.timescale.com/api/latest/hyperfunctions/

-- TimescaleDB 是 PostgreSQL 扩展，先创建普通表再转为超级表（hypertable）
-- 安装扩展
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- 基本建表 + 创建超级表
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity    DOUBLE PRECISION,
    location    TEXT
);
SELECT create_hypertable('sensor_data', 'time');

-- 指定分区间隔（chunk interval）
CREATE TABLE metrics (
    time        TIMESTAMPTZ NOT NULL,
    device_id   INT NOT NULL,
    cpu_usage   DOUBLE PRECISION,
    mem_usage   DOUBLE PRECISION
);
SELECT create_hypertable('metrics', 'time', chunk_time_interval => INTERVAL '1 day');

-- 多维分区（按时间 + 空间）
CREATE TABLE readings (
    time        TIMESTAMPTZ NOT NULL,
    device_id   INT NOT NULL,
    value       DOUBLE PRECISION
);
SELECT create_hypertable('readings', 'time', partitioning_column => 'device_id', number_partitions => 4);

-- 带约束的建表
CREATE TABLE events (
    time        TIMESTAMPTZ NOT NULL,
    event_type  TEXT NOT NULL,
    user_id     INT NOT NULL,
    payload     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (time, event_type)
);
SELECT create_hypertable('events', 'time');

-- 普通关系表（非超级表，用于维度表/查找表）
CREATE TABLE devices (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    location    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS logs (
    time        TIMESTAMPTZ NOT NULL,
    level       TEXT,
    message     TEXT
);
SELECT create_hypertable('logs', 'time', if_not_exists => TRUE);

-- CREATE TABLE AS SELECT
CREATE TABLE metrics_backup AS
SELECT * FROM metrics WHERE time > NOW() - INTERVAL '7 days';

-- 继承 PostgreSQL 全部建表语法
CREATE TABLE users (
    id          SERIAL PRIMARY KEY,
    username    VARCHAR(64) NOT NULL UNIQUE,
    email       VARCHAR(128) NOT NULL,
    age         INT CHECK (age > 0),
    balance     NUMERIC(10,2) DEFAULT 0.00,
    bio         TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 注意：超级表的主键必须包含时间列
-- 注意：create_hypertable 只能在空表上调用
-- 注意：TimescaleDB 完全兼容 PostgreSQL 的所有 CREATE TABLE 语法
-- 注意：chunk_time_interval 默认为 7 天
