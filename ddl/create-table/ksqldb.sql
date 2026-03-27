-- ksqlDB: CREATE TABLE / CREATE STREAM
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- ksqlDB 在 Apache Kafka 上提供 SQL 接口
-- 两种核心抽象：STREAM（追加流）和 TABLE（变更日志）

-- ============================================================
-- CREATE STREAM（追加型，不可变事件流）
-- ============================================================

-- 从 Kafka Topic 创建 STREAM
CREATE STREAM pageviews (
    user_id    VARCHAR KEY,
    page_url   VARCHAR,
    view_time  BIGINT
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);

-- 指定 Avro 格式
CREATE STREAM orders (
    order_id   INT KEY,
    user_id    INT,
    amount     DOUBLE,
    product    VARCHAR
) WITH (
    KAFKA_TOPIC = 'orders_topic',
    VALUE_FORMAT = 'AVRO',
    PARTITIONS = 6
);

-- 指定时间戳列
CREATE STREAM sensor_readings (
    sensor_id  VARCHAR KEY,
    reading    DOUBLE,
    ts         BIGINT
) WITH (
    KAFKA_TOPIC = 'sensor_data',
    VALUE_FORMAT = 'JSON',
    TIMESTAMP = 'ts'
);

-- ============================================================
-- CREATE TABLE（变更日志，基于 key 的最新状态）
-- ============================================================

-- 从 Kafka Topic 创建 TABLE
CREATE TABLE users (
    user_id    VARCHAR PRIMARY KEY,
    username   VARCHAR,
    email      VARCHAR,
    region     VARCHAR
) WITH (
    KAFKA_TOPIC = 'users_topic',
    VALUE_FORMAT = 'JSON'
);

-- Protobuf 格式
CREATE TABLE products (
    product_id INT PRIMARY KEY,
    name       VARCHAR,
    price      DOUBLE,
    category   VARCHAR
) WITH (
    KAFKA_TOPIC = 'products_topic',
    VALUE_FORMAT = 'PROTOBUF'
);

-- ============================================================
-- CREATE STREAM/TABLE AS SELECT（持久查询，派生流/表）
-- ============================================================

-- 从现有 STREAM 派生新 STREAM
CREATE STREAM pageviews_enriched AS
SELECT p.user_id, p.page_url, p.view_time, u.username
FROM pageviews p
LEFT JOIN users u ON p.user_id = u.user_id
EMIT CHANGES;

-- 派生物化 TABLE（聚合结果）
CREATE TABLE user_order_totals AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount
FROM orders
GROUP BY user_id
EMIT CHANGES;

-- 带过滤的派生 STREAM
CREATE STREAM high_value_orders AS
SELECT * FROM orders WHERE amount > 1000
EMIT CHANGES;

-- IF NOT EXISTS
CREATE STREAM IF NOT EXISTS events (
    event_id   VARCHAR KEY,
    event_type VARCHAR,
    payload    VARCHAR
) WITH (
    KAFKA_TOPIC = 'events_topic',
    VALUE_FORMAT = 'JSON'
);

-- OR REPLACE
CREATE OR REPLACE STREAM events_filtered AS
SELECT * FROM events WHERE event_type = 'click'
EMIT CHANGES;

-- 注意：STREAM 是追加型的（append-only），每条记录不可变
-- 注意：TABLE 是变更日志（changelog），基于 KEY 保留最新值
-- 注意：CREATE ... AS SELECT 会创建持久运行的查询
-- 注意：ksqlDB 不支持传统的 CREATE TABLE（列定义 + 存储）
-- 注意：数据格式支持 JSON, AVRO, PROTOBUF, DELIMITED, KAFKA
