-- Flink SQL: Constraints (Flink 1.11+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- PRIMARY KEY (NOT ENFORCED)
-- Flink does not enforce constraints but uses them for optimization
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users'
);

-- Composite primary key
CREATE TABLE order_items (
    order_id BIGINT,
    item_id  BIGINT,
    quantity INT,
    PRIMARY KEY (order_id, item_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'order_items'
);

-- NOT NULL
CREATE TABLE events (
    id         BIGINT NOT NULL,
    event_type STRING NOT NULL,
    event_time TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- Primary key is critical for upsert connectors
-- Without PK, upsert-kafka cannot determine which record to update
CREATE TABLE user_profiles (
    user_id  BIGINT NOT NULL,
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

-- UNIQUE constraint (not supported in Flink SQL)
-- Flink SQL only supports PRIMARY KEY as a constraint
-- Use PRIMARY KEY for key declarations:
-- CREATE TABLE users (
--     id       BIGINT,
--     username STRING,
--     email    STRING,
--     PRIMARY KEY (id) NOT ENFORCED
-- ) WITH (...);

-- ALTER TABLE to add primary key (Flink 1.17+)
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;
ALTER TABLE users DROP PRIMARY KEY;

-- Note: ALL constraints in Flink are NOT ENFORCED
-- Note: NOT ENFORCED means the system trusts the data source to maintain the constraint
-- Note: PRIMARY KEY is used for:
--   1. Changelog processing (determines update/delete key)
--   2. Lookup join optimization (efficient point queries)
--   3. Upsert mode (required for upsert-kafka connector)
--   4. Deduplication optimization
-- Note: No CHECK constraints
-- Note: No FOREIGN KEY constraints
-- Note: No DEFAULT values (data comes from external sources)
-- Note: Constraint violations will NOT raise errors; data integrity
--       must be ensured by the source system
