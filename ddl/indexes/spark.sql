-- Spark SQL: Indexes
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark SQL does NOT support traditional indexes on tables
-- It uses different optimization strategies instead

-- Partitioning (primary optimization mechanism)
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
USING PARQUET
PARTITIONED BY (order_date);

-- Bucketing (hash-based distribution for join optimization)
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    ts         TIMESTAMP
)
USING PARQUET
CLUSTERED BY (user_id) INTO 32 BUCKETS;

-- Bucketing + sorting within buckets
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    ts         TIMESTAMP
)
USING PARQUET
CLUSTERED BY (user_id) SORTED BY (ts) INTO 32 BUCKETS;

-- Data skipping via file statistics (Parquet/ORC column min/max)
-- Automatic, no explicit index creation needed

-- Delta Lake: Z-ordering (multi-dimensional clustering)
-- Databricks / Delta Lake specific
OPTIMIZE orders ZORDER BY (user_id, order_date);

-- Delta Lake: Bloom filter indexes (Databricks)
CREATE BLOOMFILTER INDEX ON TABLE orders FOR COLUMNS (user_id OPTIONS (fpp=0.1, numItems=1000000));
DROP BLOOMFILTER INDEX ON TABLE orders FOR COLUMNS (user_id);

-- Iceberg: Hidden partitioning with transforms
CREATE TABLE catalog.db.events (
    id         BIGINT,
    event_time TIMESTAMP,
    user_id    BIGINT
)
USING ICEBERG
PARTITIONED BY (days(event_time), bucket(16, user_id));

-- Hive: indexes (deprecated in Hive 3.0, removed)
-- CREATE INDEX idx_user ON TABLE users (username) AS 'COMPACT' WITH DEFERRED REBUILD;
-- This was removed; use partition pruning and file formats with statistics instead

-- View table details (file layout, statistics)
DESCRIBE EXTENDED users;
DESCRIBE FORMATTED users;
SHOW PARTITIONS orders;

-- Analyze table for optimizer statistics
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, age;
ANALYZE TABLE orders COMPUTE STATISTICS FOR ALL COLUMNS;

-- Note: Spark relies on partition pruning, file-level statistics, and
--       data layout (bucketing, Z-ordering) instead of traditional indexes
-- Note: Delta Lake adds Z-ordering and bloom filters for additional optimization
-- Note: Iceberg adds hidden partitioning with transform functions
-- Note: Use ANALYZE TABLE to generate statistics for the cost-based optimizer
