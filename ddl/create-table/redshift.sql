-- Redshift: CREATE TABLE
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- 基本建表（PostgreSQL 8.x 语法基础 + Redshift 扩展）
CREATE TABLE users (
    id         BIGINT IDENTITY(1, 1),        -- 自增列（IDENTITY 是唯一的自增方式）
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INTEGER,
    balance    DECIMAL(10, 2) DEFAULT 0.00,
    bio        VARCHAR(65535),               -- VARCHAR 最大 65535 字节
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    updated_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    PRIMARY KEY (id)
)
DISTSTYLE KEY                                -- 分布样式
DISTKEY (id)                                 -- 分布键
SORTKEY (created_at);                        -- 排序键

-- 分布样式（DISTSTYLE）
-- EVEN: 均匀分配到所有切片（默认）
-- KEY: 按指定列的值分配（相同值同一切片，优化 JOIN）
-- ALL: 每个节点一份完整拷贝（适合小维度表）
-- AUTO: Redshift 自动选择（推荐，2019+）

-- DISTSTYLE EVEN
CREATE TABLE logs (
    id         BIGINT IDENTITY(1, 1),
    message    VARCHAR(4096),
    created_at TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE EVEN;

-- DISTSTYLE ALL（适合小表）
CREATE TABLE countries (
    code       CHAR(2) NOT NULL,
    name       VARCHAR(100) NOT NULL
)
DISTSTYLE ALL;

-- DISTSTYLE AUTO（推荐，Redshift 自动选择最优分布）
CREATE TABLE orders (
    id         BIGINT IDENTITY(1, 1),
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(10, 2),
    order_date DATE
)
DISTSTYLE AUTO;

-- 排序键类型
-- SORTKEY (col): 复合排序键（Compound，默认）
-- INTERLEAVED SORTKEY (col1, col2): 交错排序键（多列等权过滤）
-- SORTKEY AUTO: 自动选择排序键

-- 复合排序键
CREATE TABLE events (
    id         BIGINT IDENTITY(1, 1),
    event_type VARCHAR(50),
    event_date DATE,
    user_id    BIGINT
)
SORTKEY (event_date, event_type);

-- 交错排序键（适合多列等权过滤，VACUUM 成本更高）
CREATE TABLE search_log (
    id         BIGINT IDENTITY(1, 1),
    category   VARCHAR(50),
    region     VARCHAR(50),
    created_at DATE
)
INTERLEAVED SORTKEY (category, region, created_at);

-- SORTKEY AUTO
CREATE TABLE auto_sorted (
    id         BIGINT IDENTITY(1, 1),
    data       VARCHAR(256)
)
SORTKEY AUTO;

-- 编码（列压缩）
CREATE TABLE compressed (
    id         BIGINT IDENTITY(1, 1) ENCODE RAW,
    name       VARCHAR(100) ENCODE ZSTD,
    status     SMALLINT ENCODE AZ64,         -- AZ64: Amazon 专有编码（推荐整数/日期）
    amount     DECIMAL(10,2) ENCODE AZ64,
    notes      VARCHAR(1000) ENCODE ZSTD,
    created_at TIMESTAMP ENCODE AZ64
);
-- 编码: RAW, BYTEDICT, DELTA, DELTA32K, LZO, MOSTLY8/16/32, RUNLENGTH, TEXT255/32K, ZSTD, AZ64
-- ENCODE AUTO 会让 Redshift 自动选择编码（默认行为）

-- CTAS（CREATE TABLE AS）
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

CREATE TABLE users_summary
DISTSTYLE KEY DISTKEY (city) SORTKEY (cnt) AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;

-- 临时表
CREATE TEMPORARY TABLE temp_users (id BIGINT, username VARCHAR(64));
-- 或
CREATE TEMP TABLE temp_staging AS SELECT * FROM users WHERE status = 1;

-- LIKE（复制表结构，包括 DISTKEY/SORTKEY/ENCODE）
CREATE TABLE users_new (LIKE users);
-- 包含定义但不包含数据

-- 外部表（Redshift Spectrum，查询 S3 数据）
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'my_glue_db'
IAM_ROLE 'arn:aws:iam::123456789012:role/MySpectrumRole';

CREATE EXTERNAL TABLE spectrum_schema.external_events (
    id         BIGINT,
    event_type VARCHAR(50),
    event_date DATE
)
STORED AS PARQUET
LOCATION 's3://my-bucket/events/';

-- 外部表（分区）
CREATE EXTERNAL TABLE spectrum_schema.partitioned_logs (
    id         BIGINT,
    message    VARCHAR(4096)
)
PARTITIONED BY (log_date DATE)
STORED AS PARQUET
LOCATION 's3://my-bucket/logs/';

ALTER TABLE spectrum_schema.partitioned_logs
ADD PARTITION (log_date='2024-01-15')
LOCATION 's3://my-bucket/logs/2024-01-15/';

-- SUPER 类型（半结构化数据，2020+）
CREATE TABLE events_json (
    id         BIGINT IDENTITY(1, 1),
    data       SUPER                        -- 存储 JSON/数组/对象
);

-- 物化视图
CREATE MATERIALIZED VIEW mv_daily_sales
DISTSTYLE KEY DISTKEY (order_date) SORTKEY (order_date) AS
SELECT order_date, SUM(amount) AS total
FROM orders
GROUP BY order_date;

-- 注意：Redshift 基于 PostgreSQL 8.0.2，但很多 PG 功能不支持
-- 注意：没有 SERIAL 类型，用 IDENTITY 代替
-- 注意：VARCHAR 最大 65535 字节（不是字符）
-- 注意：没有 ARRAY、UUID、JSONB 等 PG 类型
-- 注意：所有表都是分布式的，选择合适的 DISTKEY 对性能至关重要
-- 注意：SORTKEY 决定磁盘上数据的物理排序，影响范围查询性能
