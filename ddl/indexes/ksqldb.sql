-- ksqlDB: 索引
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- ksqlDB 不支持传统索引
-- 数据组织通过 Kafka 的分区机制实现

-- ============================================================
-- KEY 列（类似主键，用于分区）
-- ============================================================

-- STREAM 的 KEY
CREATE STREAM pageviews (
    user_id    VARCHAR KEY,          -- KEY 列，决定 Kafka 分区
    page_url   VARCHAR,
    view_time  BIGINT
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);

-- TABLE 的 PRIMARY KEY
CREATE TABLE users (
    user_id    VARCHAR PRIMARY KEY,  -- PRIMARY KEY 决定 Kafka 分区
    username   VARCHAR,
    email      VARCHAR
) WITH (
    KAFKA_TOPIC = 'users_topic',
    VALUE_FORMAT = 'JSON'
);

-- ============================================================
-- 重新分区（Re-key）——改变数据的分区方式
-- ============================================================

-- PARTITION BY：按指定列重新分区
CREATE STREAM pageviews_by_page AS
SELECT * FROM pageviews
PARTITION BY page_url
EMIT CHANGES;

-- GROUP BY 自动按分组键重新分区
CREATE TABLE page_view_counts AS
SELECT page_url, COUNT(*) AS view_count
FROM pageviews
GROUP BY page_url
EMIT CHANGES;

-- ============================================================
-- 查询优化机制
-- ============================================================

-- Pull Query（只能按 KEY/PRIMARY KEY 查询，利用 RocksDB 索引）
SELECT * FROM users WHERE user_id = 'user_123';

-- Pull Query 的 WHERE 条件必须包含 KEY
SELECT * FROM user_order_totals WHERE user_id = 'user_123';

-- Push Query（不需要索引，持续推送所有变更）
SELECT * FROM pageviews EMIT CHANGES;

-- 基于窗口的 KEY
CREATE TABLE windowed_counts AS
SELECT user_id, COUNT(*) AS cnt
FROM pageviews
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY user_id
EMIT CHANGES;

-- 按窗口和 KEY 查询
SELECT * FROM windowed_counts
WHERE user_id = 'user_123'
    AND WINDOWSTART >= '2024-01-15T00:00:00'
    AND WINDOWEND <= '2024-01-15T01:00:00';

-- 注意：ksqlDB 不支持 CREATE INDEX
-- 注意：数据通过 Kafka 分区键组织，类似分布式索引
-- 注意：Pull Query 需要按 KEY 查询（内部使用 RocksDB）
-- 注意：Push Query 是流式查询，不依赖索引
-- 注意：PARTITION BY 可重新组织数据的分区方式
