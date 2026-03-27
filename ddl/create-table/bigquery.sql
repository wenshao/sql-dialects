-- BigQuery: CREATE TABLE
--
-- 参考资料:
--   [1] BigQuery SQL Reference - CREATE TABLE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_table
--   [2] BigQuery SQL Reference - Data Types
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types

-- 基本建表
CREATE TABLE myproject.mydataset.users (
    id         INT64 NOT NULL,
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    age        INT64,
    balance    NUMERIC(10,2),               -- NUMERIC 或 BIGNUMERIC
    bio        STRING,
    tags       ARRAY<STRING>,               -- 原生数组类型
    address    STRUCT<city STRING, zip STRING>, -- 原生结构体
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 分区表（按日期分区，最常用）
CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    amount     NUMERIC(10,2),
    order_date DATE
)
PARTITION BY order_date;

-- 按 TIMESTAMP 分区（按天/小时/月/年截断）
CREATE TABLE events (
    id         INT64,
    event_time TIMESTAMP,
    data       JSON
)
PARTITION BY TIMESTAMP_TRUNC(event_time, DAY);

-- 整数范围分区
CREATE TABLE logs (
    id    INT64,
    level INT64,
    msg   STRING
)
PARTITION BY RANGE_BUCKET(level, GENERATE_ARRAY(0, 100, 10));

-- 聚集表（Clustered，提高查询性能）
CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    amount     NUMERIC(10,2),
    order_date DATE
)
PARTITION BY order_date
CLUSTER BY user_id;                         -- 最多 4 个聚集列

-- 表选项
CREATE TABLE users (
    id       INT64,
    username STRING
)
OPTIONS (
    expiration_timestamp = TIMESTAMP '2025-12-31 00:00:00 UTC',
    description = 'User table',
    labels = [('env', 'prod')]
);

-- CREATE TABLE AS SELECT (CTAS)
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- CREATE OR REPLACE
CREATE OR REPLACE TABLE users (id INT64, username STRING);

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id INT64, username STRING);

-- 外部表（查询 GCS/Drive 中的文件）
CREATE EXTERNAL TABLE external_data
OPTIONS (
    format = 'CSV',
    uris = ['gs://bucket/path/*.csv']
);

-- 注意：BigQuery 没有主键、唯一约束（仅信息性，不强制执行）
-- 注意：没有自增列
-- 注意：没有索引（通过分区和聚集优化查询）
-- 注意：列名大小写不敏感
