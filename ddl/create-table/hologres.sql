-- Hologres: CREATE TABLE
--
-- 参考资料:
--   [1] Hologres SQL - CREATE TABLE
--       https://help.aliyun.com/zh/hologres/user-guide/create-table
--   [2] Hologres - Data Types
--       https://help.aliyun.com/zh/hologres/user-guide/data-types

-- 行存表（适合点查）
CREATE TABLE users (
    id         BIGINT NOT NULL,
    username   TEXT NOT NULL,
    email      TEXT NOT NULL,
    age        INT,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);
CALL set_table_property('users', 'orientation', 'row');

-- 列存表（适合分析查询，默认）
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    user_id    BIGINT NOT NULL,
    amount     NUMERIC(10,2),
    order_date DATE NOT NULL,
    PRIMARY KEY (id)
);
CALL set_table_property('orders', 'orientation', 'column');
CALL set_table_property('orders', 'clustering_key', 'order_date');
CALL set_table_property('orders', 'segment_key', 'order_date');
CALL set_table_property('orders', 'bitmap_columns', 'user_id');
CALL set_table_property('orders', 'dictionary_encoding_columns', 'user_id');

-- 行列混存（Hologres 2.0+，同时满足点查和分析）
CREATE TABLE users_hybrid (
    id         BIGINT NOT NULL,
    username   TEXT NOT NULL,
    email      TEXT NOT NULL,
    age        INT,
    PRIMARY KEY (id)
);
CALL set_table_property('users_hybrid', 'orientation', 'row,column');

-- 分区表
CREATE TABLE orders_partitioned (
    id         BIGINT NOT NULL,
    user_id    BIGINT,
    amount     NUMERIC(10,2),
    order_date DATE NOT NULL,
    PRIMARY KEY (id, order_date)              -- 分区键必须在主键中
)
PARTITION BY LIST (order_date);

-- 创建分区
CREATE TABLE orders_partitioned_20240115 PARTITION OF orders_partitioned
FOR VALUES IN ('2024-01-15');

-- 分布键（Distribution Key）
CALL set_table_property('users', 'distribution_key', 'id');

-- 事件时间列（Event Time Column，用于数据过期）
CALL set_table_property('orders', 'event_time_column', 'order_date');
CALL set_table_property('orders', 'time_to_live_in_seconds', '2592000'); -- 30 天

-- Binlog（用于实时消费变更）
CALL set_table_property('users', 'binlog.level', 'replica');
CALL set_table_property('users', 'binlog.ttl', '86400');

-- 外部表（关联 MaxCompute）
CREATE FOREIGN TABLE mc_users (
    id       BIGINT,
    username TEXT,
    email    TEXT
)
SERVER odps_server
OPTIONS (project_name 'myproject', table_name 'users');

-- CTAS
CREATE TABLE users_backup AS SELECT * FROM users WHERE created_at > '2024-01-01';

-- 数据类型（兼容 PostgreSQL）：
-- INT / BIGINT / SMALLINT: 整数
-- REAL / DOUBLE PRECISION / FLOAT: 浮点
-- NUMERIC(P,S) / DECIMAL(P,S): 定点
-- TEXT / VARCHAR(N) / CHAR(N): 字符串
-- BOOLEAN: 布尔
-- DATE / TIMESTAMP / TIMESTAMPTZ: 时间
-- BYTEA: 二进制
-- JSON / JSONB: JSON
-- INT[] / TEXT[]: 数组
-- SERIAL / BIGSERIAL: 自增

-- 注意：Hologres 兼容 PostgreSQL 协议和语法
-- 注意：PRIMARY KEY 是强制执行的（与 BigQuery/Snowflake 不同）
-- 注意：通过 set_table_property 设置表属性是 Hologres 的核心用法
