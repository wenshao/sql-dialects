-- Greenplum: CREATE TABLE
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- 基本表（Hash 分布，默认）
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INTEGER,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
)
DISTRIBUTED BY (id);

-- 随机分布（无分布键时使用）
CREATE TABLE logs (
    id         BIGSERIAL,
    message    TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
DISTRIBUTED RANDOMLY;

-- 复制表（小维表广播到所有节点）
CREATE TABLE regions (
    id         INTEGER PRIMARY KEY,
    name       VARCHAR(64) NOT NULL
)
DISTRIBUTED REPLICATED;

-- 分区表（Range 分区）
CREATE TABLE orders (
    id         BIGSERIAL,
    user_id    BIGINT NOT NULL,
    amount     NUMERIC(10,2),
    order_date DATE NOT NULL
)
DISTRIBUTED BY (user_id)
PARTITION BY RANGE (order_date) (
    PARTITION p2024_01 START ('2024-01-01') END ('2024-02-01'),
    PARTITION p2024_02 START ('2024-02-01') END ('2024-03-01'),
    PARTITION p2024_03 START ('2024-03-01') END ('2024-04-01'),
    DEFAULT PARTITION other
);

-- List 分区
CREATE TABLE events_by_region (
    event_id   BIGSERIAL,
    region     VARCHAR(64) NOT NULL,
    event_name VARCHAR(128)
)
DISTRIBUTED BY (event_id)
PARTITION BY LIST (region) (
    PARTITION p_cn VALUES ('cn-beijing', 'cn-shanghai'),
    PARTITION p_us VALUES ('us-east', 'us-west'),
    DEFAULT PARTITION other
);

-- Append-Optimized (AO) 表（批量加载优化）
CREATE TABLE events_ao (
    id         BIGINT,
    event_name VARCHAR(128),
    event_time TIMESTAMP
)
WITH (appendoptimized=true)
DISTRIBUTED BY (id);

-- 列存储 AO 表（分析查询优化）
CREATE TABLE events_column (
    id         BIGINT,
    event_name VARCHAR(128),
    event_time TIMESTAMP
)
WITH (appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5)
DISTRIBUTED BY (id);

-- 外部表（gpfdist 加载）
CREATE READABLE EXTERNAL TABLE ext_users (
    id         BIGINT,
    username   VARCHAR(64),
    email      VARCHAR(255)
)
LOCATION ('gpfdist://etl_host:8081/users.csv')
FORMAT 'CSV' (HEADER DELIMITER ',');

-- 可写外部表
CREATE WRITABLE EXTERNAL TABLE ext_export (
    id         BIGINT,
    username   VARCHAR(64)
)
LOCATION ('gpfdist://etl_host:8081/export.csv')
FORMAT 'CSV'
DISTRIBUTED BY (id);

-- PXF 外部表（访问 HDFS/S3/Hive）
-- CREATE EXTERNAL TABLE pxf_hive_table (id INT, name TEXT)
-- LOCATION ('pxf://hive_db.hive_table?PROFILE=Hive')
-- FORMAT 'CUSTOM' (FORMATTER='pxfwritable_import');

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01'
DISTRIBUTED BY (id);

-- 临时表
CREATE TEMP TABLE tmp_import (
    id BIGINT, name VARCHAR(64)
)
DISTRIBUTED RANDOMLY;

-- 注意：Greenplum 基于 PostgreSQL，支持大部分 PG 语法
-- 注意：分布键选择影响 JOIN 性能（相同分布键的表 JOIN 可本地执行）
-- 注意：PRIMARY KEY / UNIQUE 约束必须包含分布键列
