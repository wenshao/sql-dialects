-- StarRocks: CREATE TABLE
--
-- 参考资料:
--   [1] StarRocks - CREATE TABLE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_TABLE/
--   [2] StarRocks - Data Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/
--   [3] StarRocks - Table Design
--       https://docs.starrocks.io/docs/table_design/table_types/

-- 明细模型（Duplicate Key，保留所有行）
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

-- 聚合模型（Aggregate Key，按维度列聚合）
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

-- 更新模型（Unique Key，按主键保留最新行）
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

-- 主键模型（Primary Key，支持实时更新，1.19+）
CREATE TABLE users_pk (
    id         BIGINT NOT NULL,
    username   VARCHAR(64),
    email      VARCHAR(255),
    age        INT,
    updated_at DATETIME
)
PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
ORDER BY (username)
PROPERTIES ("replication_num" = "3");

-- 分区表
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

-- CTAS（3.0+ 支持自动推断分布策略，早期版本需显式指定 DISTRIBUTED BY）
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

-- 外部表（3.0+ 推荐用 Catalog 代替）
-- CREATE EXTERNAL CATALOG hive_catalog PROPERTIES (...);

-- 数据类型：
-- TINYINT / SMALLINT / INT / BIGINT / LARGEINT: 整数
-- FLOAT / DOUBLE: 浮点
-- DECIMAL(P,S): 定点
-- CHAR(N) / VARCHAR(N) / STRING: 字符串
-- DATE / DATETIME: 日期时间
-- BOOLEAN: 布尔
-- ARRAY<T> / MAP<K,V> / STRUCT<...> / JSON: 复合类型
-- BITMAP / HLL: 特殊聚合类型
