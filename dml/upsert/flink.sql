-- Flink SQL: UPSERT (Flink 1.12+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink has no MERGE statement or ON CONFLICT clause
-- Upsert is achieved through connector semantics and primary keys

-- 1. Upsert via upsert-kafka connector
-- Records with the same key automatically replace previous values
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

-- Writing latest state produces upsert behavior
INSERT INTO user_profiles
SELECT user_id, LAST_VALUE(username), LAST_VALUE(email)
FROM user_events
GROUP BY user_id;

-- 2. Upsert via JDBC connector with PRIMARY KEY
-- JDBC sink auto-detects primary key and uses INSERT ON DUPLICATE KEY / UPSERT
CREATE TABLE user_summary (
    user_id      BIGINT,
    order_count  BIGINT,
    total_amount DECIMAL(10,2),
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'user_summary'
);

-- Aggregation result automatically upserts into the database
INSERT INTO user_summary
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 3. Changelog-based upsert
-- Flink's internal changelog stream (+I, -U, +U, -D) naturally handles upserts
-- Any aggregation or join that produces updates emits changelog records

-- Example: Deduplication (keep latest record per key)
INSERT INTO deduplicated_events
SELECT user_id, event_type, event_time
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM events
)
WHERE rn = 1;

-- 4. Temporal table updates (lookup table that changes over time)
CREATE TABLE dim_products (
    product_id BIGINT,
    name       STRING,
    price      DECIMAL(10,2),
    PRIMARY KEY (product_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'products',
    'lookup.cache.max-rows' = '5000',
    'lookup.cache.ttl' = '10min'
);
-- Lookup joins against this table always get the latest version

-- 5. Elasticsearch sink (natural upsert by document ID)
CREATE TABLE es_users (
    user_id  BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'elasticsearch-7',
    'hosts' = 'http://localhost:9200',
    'index' = 'users'
);
-- Documents are automatically upserted by user_id

-- Note: Flink achieves upsert through connector-level semantics, not SQL syntax
-- Note: PRIMARY KEY declaration is essential for upsert behavior
-- Note: The upsert-kafka connector is the primary way to do upserts in streaming
-- Note: JDBC sinks with PK automatically translate changelog to INSERT/UPDATE/DELETE
-- Note: No MERGE INTO or ON CONFLICT syntax
-- Note: No RETURNING clause
