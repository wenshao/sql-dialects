-- Apache Doris: CREATE TABLE
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Duplicate Key 模型（保留所有行，默认模型）
CREATE TABLE users (
    id         BIGINT NOT NULL,
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT '0.00',
    bio        STRING,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- Aggregate Key 模型（按维度列聚合）
CREATE TABLE daily_stats (
    date       DATE NOT NULL,
    user_id    BIGINT NOT NULL,
    clicks     BIGINT SUM DEFAULT '0',        -- 聚合方式：SUM
    revenue    DECIMAL(10,2) SUM DEFAULT '0',
    last_visit DATETIME REPLACE                -- 聚合方式：REPLACE
)
AGGREGATE KEY(date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- Unique Key 模型（按主键保留最新行）
CREATE TABLE users_unique (
    id         BIGINT NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- Primary Key 模型（1.2+，Merge-on-Write，实时更新）
-- 注意：Doris 2.1+ 的 Unique Key 默认启用 Merge-on-Write
CREATE TABLE users_pk (
    id         BIGINT NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES (
    "replication_num" = "3",
    "enable_unique_key_merge_on_write" = "true"
);

-- 分区表（Range 分区）
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(10,2),
    order_date DATE NOT NULL
)
DUPLICATE KEY(id)
PARTITION BY RANGE(order_date) (
    PARTITION p2024_01 VALUES LESS THAN ('2024-02-01'),
    PARTITION p2024_02 VALUES LESS THAN ('2024-03-01'),
    PARTITION p2024_03 VALUES LESS THAN ('2024-04-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- List 分区（2.0+）
CREATE TABLE events_by_region (
    event_id   BIGINT NOT NULL,
    region     VARCHAR(64) NOT NULL,
    event_name VARCHAR(128)
)
DUPLICATE KEY(event_id)
PARTITION BY LIST(region) (
    PARTITION p_cn VALUES IN ('cn-beijing', 'cn-shanghai'),
    PARTITION p_us VALUES IN ('us-east', 'us-west')
)
DISTRIBUTED BY HASH(event_id) BUCKETS 8;

-- 动态分区
CREATE TABLE orders_dynamic (
    id         BIGINT,
    order_date DATE
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- CTAS
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- 外部表（Multi Catalog，2.0+）
-- CREATE CATALOG hive_catalog PROPERTIES (
--     'type' = 'hms',
--     'hive.metastore.uris' = 'thrift://metastore:9083'
-- );
-- SELECT * FROM hive_catalog.db.table;

-- 数据类型：
-- TINYINT / SMALLINT / INT / BIGINT / LARGEINT: 整数
-- FLOAT / DOUBLE: 浮点
-- DECIMAL(P,S): 定点
-- CHAR(N) / VARCHAR(N) / STRING: 字符串
-- DATE / DATETIME: 日期时间
-- BOOLEAN: 布尔
-- ARRAY<T> / MAP<K,V> / STRUCT<...> / JSON: 复合类型（2.0+）
-- BITMAP / HLL / QUANTILE_STATE: 特殊聚合类型
