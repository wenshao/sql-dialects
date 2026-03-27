-- Trino (formerly PrestoSQL): CREATE TABLE
--
-- 参考资料:
--   [1] Trino - CREATE TABLE
--       https://trino.io/docs/current/sql/create-table.html
--   [2] Trino - Data Types
--       https://trino.io/docs/current/language/types.html

-- 基本建表（取决于底层 Connector）
CREATE TABLE users (
    id         BIGINT,
    username   VARCHAR,
    email      VARCHAR,
    age        INTEGER,
    balance    DECIMAL(10,2),
    bio        VARCHAR,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- 使用 Hive Connector（最常见）
CREATE TABLE hive.mydb.users (
    id         BIGINT,
    username   VARCHAR,
    email      VARCHAR,
    age        INTEGER,
    created_at TIMESTAMP,
    dt         VARCHAR                      -- 分区列必须在列定义中声明
)
WITH (
    format = 'ORC',                         -- PARQUET, ORC, AVRO, JSON, CSV
    partitioned_by = ARRAY['dt'],           -- 分区列在 WITH 中引用已声明的列
    bucketed_by = ARRAY['id'],
    bucket_count = 256
);

-- 注意：Trino Hive Connector 分区列必须先在列定义中声明，再在 WITH 中引用

-- 使用 Iceberg Connector（推荐，支持更多特性）
CREATE TABLE iceberg.mydb.orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['month(order_date)'],  -- Iceberg 支持转换分区
    sorted_by = ARRAY['user_id']
);

-- Iceberg 分区转换：
-- year(col), month(col), day(col), hour(col)
-- bucket(N, col)
-- truncate(N, col)

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > TIMESTAMP '2024-01-01 00:00:00';

-- CREATE TABLE ... WITH NO DATA（只复制结构）
CREATE TABLE users_empty AS
SELECT * FROM users WITH NO DATA;

-- CREATE OR REPLACE（Iceberg Connector）
CREATE OR REPLACE TABLE users (id BIGINT, username VARCHAR);

-- Delta Lake Connector
CREATE TABLE delta.mydb.events (
    id         BIGINT,
    event_type VARCHAR,
    event_time TIMESTAMP
)
WITH (
    location = 's3://bucket/delta/events/',
    partitioned_by = ARRAY['event_type']
);

-- Memory Connector（测试用）
CREATE TABLE memory.default.temp (id BIGINT, name VARCHAR);

-- 数据类型：
-- BOOLEAN: 布尔
-- TINYINT / SMALLINT / INTEGER / BIGINT: 整数
-- REAL / DOUBLE: 浮点
-- DECIMAL(P,S): 定点
-- VARCHAR / CHAR(N): 字符串
-- VARBINARY: 二进制
-- DATE / TIME / TIMESTAMP / TIMESTAMP WITH TIME ZONE: 时间
-- ARRAY(T) / MAP(K,V) / ROW(name T, ...): 复合类型
-- JSON: JSON
-- UUID: UUID
-- IPADDRESS: IP 地址

-- 注意：Trino 本身是查询引擎，不存储数据
-- 注意：DDL 能力取决于底层 Connector
-- 注意：没有主键、索引、约束等概念
-- 注意：UPDATE/DELETE 支持取决于 Connector（Iceberg/Delta/Hive ACID/RDBMS 等支持）
