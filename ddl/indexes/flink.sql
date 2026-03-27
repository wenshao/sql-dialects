-- Flink SQL: Indexes
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL does NOT support indexes
-- As a stream processing engine, Flink processes data in-flight
-- and does not maintain persistent index structures

-- Instead, Flink uses these optimization strategies:

-- 1. Primary key declaration (semantic hint, not enforced)
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users'
);
-- The PRIMARY KEY helps Flink optimize changelog processing and lookup joins

-- 2. Lookup joins use the source system's indexes
-- When performing a lookup join against a JDBC table,
-- the database's own indexes are used for point queries
CREATE TABLE dim_users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users',
    'lookup.cache.max-rows' = '5000',
    'lookup.cache.ttl' = '10min'
);
-- The lookup join benefits from indexes on the MySQL side

-- 3. State backend configuration (optimizes stateful operations)
-- SET 'state.backend' = 'rocksdb';
-- SET 'state.backend.incremental' = 'true';
-- RocksDB uses LSM-tree internally, no user-level index control

-- 4. Partitioning for filesystem tables
CREATE TABLE logs (
    log_time   TIMESTAMP(3),
    level      STRING,
    message    STRING,
    dt         STRING,
    hr         STRING
) PARTITIONED BY (dt, hr) WITH (
    'connector' = 'filesystem',
    'path' = '/data/logs/',
    'format' = 'parquet'
);
-- Partition pruning helps skip irrelevant files

-- 5. Table hints for optimization (Flink 1.15+)
SELECT /*+ LOOKUP('table'='dim_users', 'retry-predicate'='lookup_miss',
           'retry-strategy'='fixed_delay', 'fixed-delay'='10s', 'max-attempts'='3') */
    e.*, d.username
FROM events AS e
JOIN dim_users FOR SYSTEM_TIME AS OF e.proc_time AS d
ON e.user_id = d.id;

-- Note: Flink has no CREATE INDEX or DROP INDEX statements
-- Note: Optimization comes from proper key declarations, partitioning,
--       lookup caching, and leveraging external system indexes
-- Note: For stateful operations, Flink manages internal state using
--       configurable state backends (HashMap, RocksDB)
