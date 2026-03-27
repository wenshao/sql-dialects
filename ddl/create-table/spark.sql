-- Spark SQL: CREATE TABLE (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Managed table (Spark manages data and metadata)
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT,
    balance    DECIMAL(10,2),
    bio        STRING,
    created_at TIMESTAMP
)
USING PARQUET;

-- External table (Spark only manages metadata)
CREATE EXTERNAL TABLE logs (
    log_date   STRING,
    message    STRING,
    level      STRING
)
STORED AS PARQUET
LOCATION '/data/logs/';

-- Hive-format table
CREATE TABLE events (
    id         BIGINT,
    event_name STRING,
    payload    STRING
)
STORED AS ORC
TBLPROPERTIES ('orc.compress' = 'SNAPPY');

-- Partitioned table
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
USING PARQUET
PARTITIONED BY (order_date);

-- Bucketed table (for optimized joins)
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    ts         TIMESTAMP
)
USING PARQUET
CLUSTERED BY (user_id) INTO 32 BUCKETS;

-- CTAS (Create Table As Select)
CREATE TABLE active_users AS
SELECT * FROM users WHERE status = 1;

CREATE TABLE top_users
USING PARQUET
PARTITIONED BY (city)
AS SELECT * FROM users WHERE age > 25;

-- Create from CSV / JSON / Parquet
CREATE TABLE sales
USING CSV
OPTIONS (header 'true', inferSchema 'true', path '/data/sales.csv');

CREATE TABLE events
USING JSON
OPTIONS (path '/data/events.json');

-- Delta Lake table (Databricks / Delta Lake)
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING
)
USING DELTA
LOCATION '/delta/users';

-- Iceberg table (Spark 3.0+ with Iceberg catalog)
CREATE TABLE catalog.db.users (
    id       BIGINT,
    username STRING,
    email    STRING
)
USING ICEBERG
PARTITIONED BY (bucket(16, id));

-- Temporary view (no temp tables, use views instead)
CREATE TEMPORARY VIEW tmp_users AS
SELECT * FROM users WHERE status = 1;

CREATE OR REPLACE TEMP VIEW tmp_users AS
SELECT * FROM users WHERE status = 1;

-- Global temporary view (cross-session in same application)
CREATE GLOBAL TEMPORARY VIEW global_users AS
SELECT * FROM users;
-- Access with: SELECT * FROM global_temp.global_users;

-- CREATE TABLE IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (
    id       BIGINT,
    username STRING
) USING PARQUET;

-- Table with comments
CREATE TABLE users (
    id       BIGINT COMMENT 'Primary key',
    username STRING COMMENT 'Unique username'
)
USING PARQUET
COMMENT 'User accounts table';

-- REPLACE TABLE (Spark 3.0+, Delta Lake)
CREATE OR REPLACE TABLE users (
    id       BIGINT,
    username STRING
) USING DELTA;

-- Note: Spark SQL has no PRIMARY KEY or UNIQUE constraints (except Delta Lake 3.0+)
-- Note: No SERIAL / auto-increment; use monotonically_increasing_id() or row_number()
-- Note: Spark uses STRING instead of VARCHAR/TEXT
-- Note: Managed tables are stored in Spark's warehouse directory
