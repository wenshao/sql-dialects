-- Flink SQL: UPDATE (Flink 1.17+, limited support)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- UPDATE is only supported in batch mode for certain connectors
-- Streaming tables (Kafka) do NOT support UPDATE

-- JDBC connector: Basic update (batch mode)
UPDATE users SET age = 26 WHERE username = 'alice';

-- JDBC connector: Multi-column update (batch mode)
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- For streaming scenarios, "updates" are handled differently:

-- 1. Upsert pattern: Use upsert-kafka connector
-- New records with the same key overwrite previous ones
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

-- Writing an updated record (upsert semantics)
INSERT INTO user_profiles
SELECT user_id, latest_username, latest_email
FROM (
    SELECT user_id,
           LAST_VALUE(username) AS latest_username,
           LAST_VALUE(email) AS latest_email
    FROM user_events
    GROUP BY user_id
);

-- 2. Changelog streams: Emit update/delete messages
-- Flink internally uses changelog (+I, -U, +U, -D) for stateful operations
-- Aggregations naturally produce update messages:
INSERT INTO user_stats
SELECT user_id, COUNT(*) AS event_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;
-- This emits updates whenever the count/sum changes

-- 3. JDBC sink with primary key (auto-upsert)
CREATE TABLE user_summary (
    user_id     BIGINT,
    total_orders BIGINT,
    total_amount DECIMAL(10,2),
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'user_summary'
);
-- Aggregation results automatically upsert into MySQL:
INSERT INTO user_summary
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

-- Note: Traditional UPDATE is only available in batch mode (Flink 1.17+)
-- Note: Streaming tables use upsert semantics via changelog streams
-- Note: Kafka topics are append-only; "updates" are new records with same key
-- Note: JDBC sinks with PRIMARY KEY automatically perform upsert
-- Note: No RETURNING clause
-- Note: No UPDATE ... FROM (multi-table update)
-- Note: UPDATE on streaming sources will cause an error
