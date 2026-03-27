-- Databricks SQL: CREATE TABLE
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- 基本建表（Delta Lake 格式，默认）
CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,  -- 自增列
    username   STRING NOT NULL,
    email      STRING NOT NULL,
    age        INT,
    balance    DECIMAL(10, 2) DEFAULT 0.00,
    bio        STRING,                       -- STRING 无长度限制
    created_at TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp(),
    CONSTRAINT pk_users PRIMARY KEY (id)
);

-- Delta Lake 是默认存储格式，提供 ACID、Time Travel、Schema Evolution

-- Unity Catalog 三级命名空间
-- catalog.schema.table
CREATE TABLE my_catalog.my_schema.users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    username   STRING NOT NULL
);

-- GENERATED ALWAYS AS（计算列）
CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id    BIGINT NOT NULL,
    quantity   INT,
    unit_price DECIMAL(10, 2),
    total      DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * unit_price),
    order_date DATE,
    order_year INT GENERATED ALWAYS AS (YEAR(order_date))
);

-- 分区（传统分区，适合高基数列如日期）
CREATE TABLE events (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    event_type STRING,
    event_date DATE,
    user_id    BIGINT,
    data       STRING
)
PARTITIONED BY (event_date);

-- Liquid Clustering（取代分区和 ZORDER，Databricks 2023+，推荐）
CREATE TABLE events_v2 (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    event_type STRING,
    event_date DATE,
    user_id    BIGINT,
    data       STRING
)
CLUSTER BY (event_date, event_type);

-- 修改 Liquid Clustering 键
ALTER TABLE events_v2 CLUSTER BY (event_date, user_id);
-- 取消 Liquid Clustering
ALTER TABLE events_v2 CLUSTER BY NONE;

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

CREATE OR REPLACE TABLE users_summary AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;

-- CREATE TABLE LIKE
CREATE TABLE users_new LIKE users;

-- CLONE（深拷贝，包含完整数据复制）
CREATE TABLE users_clone DEEP CLONE users;

-- SHALLOW CLONE（浅拷贝，共享底层数据文件）
CREATE TABLE users_shallow SHALLOW CLONE users;

-- 时间旅行克隆
CREATE TABLE users_snapshot DEEP CLONE users VERSION AS OF 5;
CREATE TABLE users_snapshot2 DEEP CLONE users TIMESTAMP AS OF '2024-01-15 10:00:00';

-- 临时视图（Databricks 没有临时表概念，用临时视图代替）
CREATE TEMPORARY VIEW temp_users AS
SELECT * FROM users WHERE status = 1;

-- 表属性
CREATE TABLE logs (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    message    STRING,
    created_at TIMESTAMP
)
TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',     -- 自动优化写入
    'delta.autoOptimize.autoCompact' = 'true',       -- 自动压缩小文件
    'delta.logRetentionDuration' = 'interval 30 days',
    'delta.deletedFileRetentionDuration' = 'interval 7 days'
);

-- 外部表（读取外部数据源）
CREATE TABLE external_events (
    id         BIGINT,
    event_type STRING,
    event_date DATE
)
USING PARQUET
LOCATION 's3://my-bucket/events/';

-- 使用不同文件格式
CREATE TABLE csv_data (
    col1 STRING,
    col2 INT
)
USING CSV
OPTIONS (header 'true', delimiter ',')
LOCATION 's3://my-bucket/csv-data/';

-- 表注释
CREATE TABLE users_v2 (
    id         BIGINT COMMENT 'Unique identifier',
    username   STRING COMMENT 'Login name'
)
COMMENT 'User information table';

-- Delta Lake 维护命令
-- OPTIMIZE（合并小文件）
OPTIMIZE events;
OPTIMIZE events WHERE event_date >= '2024-01-01';

-- Z-ORDER（数据布局优化，与传统分区搭配使用）
OPTIMIZE events ZORDER BY (user_id, event_type);

-- VACUUM（清理过期文件）
VACUUM events;
VACUUM events RETAIN 168 HOURS;  -- 默认 7 天

-- 注意：Delta Lake 是 Databricks 的核心，所有表默认使用 Delta 格式
-- 注意：没有传统索引（通过 Liquid Clustering / Z-ORDER 优化数据布局）
-- 注意：Liquid Clustering 是推荐的分区替代方案（更灵活，自动维护）
-- 注意：GENERATED ALWAYS AS IDENTITY 不保证连续（分布式系统）
-- 注意：DEEP CLONE 和 SHALLOW CLONE 是 Delta Lake 特有功能
-- 注意：Unity Catalog 提供细粒度权限和数据治理
