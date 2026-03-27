-- Flink SQL: CREATE TABLE (Flink 1.11+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Kafka source table
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    event_time TIMESTAMP(3),
    payload    STRING,
    -- Watermark for event-time processing
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'user-events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-consumer',
    'format' = 'json',
    'scan.startup.mode' = 'latest-offset'
);

-- Kafka sink table
CREATE TABLE output_events (
    user_id    BIGINT,
    event_type STRING,
    event_count BIGINT,
    window_end TIMESTAMP(3)
) WITH (
    'connector' = 'kafka',
    'topic' = 'output-events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- JDBC connector (MySQL/PostgreSQL source/sink)
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT,
    created_at TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users',
    'username' = 'root',
    'password' = 'password'
);

-- Filesystem connector (CSV/Parquet/JSON)
CREATE TABLE sales (
    product_id BIGINT,
    amount     DECIMAL(10,2),
    sale_date  DATE
) WITH (
    'connector' = 'filesystem',
    'path' = '/data/sales/',
    'format' = 'parquet'
);

-- Filesystem with partitioning
CREATE TABLE logs (
    log_time   TIMESTAMP(3),
    level      STRING,
    message    STRING,
    dt         STRING,
    hr         STRING
) PARTITIONED BY (dt, hr) WITH (
    'connector' = 'filesystem',
    'path' = '/data/logs/',
    'format' = 'json',
    'sink.partition-commit.trigger' = 'process-time',
    'sink.partition-commit.delay' = '1 h',
    'sink.partition-commit.policy.kind' = 'success-file'
);

-- Processing-time attribute
CREATE TABLE sensor_readings (
    sensor_id  STRING,
    temperature DOUBLE,
    proc_time  AS PROCTIME()   -- Processing-time attribute (virtual column)
) WITH (
    'connector' = 'kafka',
    'topic' = 'sensors',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- Upsert Kafka (Flink 1.12+)
CREATE TABLE user_profiles (
    user_id  BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-profiles',
    'properties.bootstrap.servers' = 'kafka:9092',
    'key.format' = 'json',
    'value.format' = 'json'
);

-- Datagen connector (testing/development)
CREATE TABLE test_data (
    id         BIGINT,
    name       STRING,
    created_at TIMESTAMP(3),
    WATERMARK FOR created_at AS created_at - INTERVAL '1' SECOND
) WITH (
    'connector' = 'datagen',
    'rows-per-second' = '100',
    'fields.id.kind' = 'sequence',
    'fields.id.start' = '1',
    'fields.id.end' = '1000000',
    'fields.name.length' = '10'
);

-- Print connector (for debugging sink)
CREATE TABLE debug_output (
    id   BIGINT,
    data STRING
) WITH (
    'connector' = 'print'
);

-- Temporary table
CREATE TEMPORARY TABLE tmp_results (
    id    BIGINT,
    total DECIMAL(10,2)
) WITH (
    'connector' = 'blackhole'   -- Discards all data
);

-- CREATE TABLE LIKE (copy schema from another table)
CREATE TABLE user_events_copy (LIKE user_events);

-- Computed columns
CREATE TABLE enriched_events (
    user_id    BIGINT,
    event_time TIMESTAMP(3),
    event_date AS CAST(event_time AS DATE),          -- Computed column
    event_hour AS EXTRACT(HOUR FROM event_time),     -- Computed column
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- Metadata columns (Flink 1.12+)
CREATE TABLE kafka_events (
    user_id    BIGINT,
    event_type STRING,
    event_time TIMESTAMP(3),
    kafka_topic  STRING METADATA FROM 'topic' VIRTUAL,
    kafka_offset BIGINT METADATA FROM 'offset' VIRTUAL,
    kafka_ts     TIMESTAMP(3) METADATA FROM 'timestamp' VIRTUAL,
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- Note: Flink tables require a WITH clause specifying the connector
-- Note: PRIMARY KEY ... NOT ENFORCED is used for semantic hints, not enforcement
-- Note: No SERIAL / auto-increment; IDs come from source systems
-- Note: No CREATE OR REPLACE TABLE; use DROP + CREATE
-- Note: Watermarks are critical for event-time windowed operations
