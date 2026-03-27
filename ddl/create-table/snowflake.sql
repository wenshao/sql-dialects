-- Snowflake: CREATE TABLE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table
--   [2] Snowflake SQL Reference - Data Types
--       https://docs.snowflake.com/en/sql-reference/data-types

-- 基本建表
CREATE TABLE users (
    id         NUMBER(19,0) NOT NULL AUTOINCREMENT,
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        NUMBER(10,0),
    balance    NUMBER(10,2) DEFAULT 0.00,
    bio        VARCHAR,                     -- VARCHAR 不指定长度默认 16MB
    tags       VARIANT,                     -- 半结构化数据（JSON/ARRAY/OBJECT）
    created_at TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (id),
    UNIQUE (username),
    UNIQUE (email)
);

-- 注意：PRIMARY KEY 和 UNIQUE 是信息性约束，不强制执行！

-- 临时表
CREATE TEMPORARY TABLE temp_users (id NUMBER, username VARCHAR);
-- 会话结束自动删除

-- 瞬态表（Transient，没有 Fail-safe 保护期）
CREATE TRANSIENT TABLE staging_data (id NUMBER, data VARIANT);

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- CLONE（零拷贝克隆，Snowflake 特色功能）
CREATE TABLE users_clone CLONE users;
CREATE TABLE users_clone CLONE users AT (TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP);

-- CREATE OR REPLACE
CREATE OR REPLACE TABLE users (id NUMBER, username VARCHAR);

-- LIKE（复制表结构）
CREATE TABLE users_new LIKE users;

-- 聚集键（Cluster Key）
CREATE TABLE orders (
    id         NUMBER AUTOINCREMENT,
    user_id    NUMBER,
    amount     NUMBER(10,2),
    order_date DATE
)
CLUSTER BY (order_date, user_id);

-- 外部表（查询 S3/Azure/GCS 的文件）
CREATE EXTERNAL TABLE external_data (
    col1 VARCHAR AS (value:c1::VARCHAR),
    col2 NUMBER AS (value:c2::NUMBER)
)
LOCATION = @my_stage/path/
FILE_FORMAT = (TYPE = 'CSV');

-- 数据保留（Time Travel）
CREATE TABLE important_data (id NUMBER, data VARCHAR)
DATA_RETENTION_TIME_IN_DAYS = 90;          -- 默认 1 天，最多 90 天

-- 标签
CREATE TABLE users (id NUMBER, username VARCHAR)
COMMENT = 'User information table';
ALTER TABLE users SET TAG cost_center = 'engineering';

-- IDENTITY 列
CREATE TABLE t (
    id NUMBER AUTOINCREMENT START 1 INCREMENT 1,  -- 或 IDENTITY
    name VARCHAR
);
