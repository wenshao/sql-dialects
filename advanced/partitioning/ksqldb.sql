-- ksqlDB: 表分区策略
--
-- 参考资料:
--   [1] ksqlDB Documentation
--       https://docs.ksqldb.io/en/latest/

-- ksqlDB 使用 Kafka 分区，不是数据库分区

-- ============================================================
-- Kafka Topic 分区
-- ============================================================

-- 创建流时指定 KEY（影响 Kafka 分区）
CREATE STREAM orders (
    order_id VARCHAR KEY, user_id VARCHAR, amount DOUBLE
) WITH (
    kafka_topic = 'orders',
    value_format = 'JSON',
    partitions = 8
);

-- ============================================================
-- 重分区（PARTITION BY）
-- ============================================================

CREATE STREAM orders_by_user AS
SELECT * FROM orders PARTITION BY user_id
EMIT CHANGES;

-- 数据按 user_id 重新分区到 Kafka Topic

-- ============================================================
-- 聚合表的分区
-- ============================================================

CREATE TABLE user_counts AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
EMIT CHANGES;

-- 表的分区由 GROUP BY 键决定

-- 注意：ksqlDB 的"分区"是 Kafka Topic 分区
-- 注意：PARTITION BY 重新分区数据到新的 Topic
-- 注意：聚合表按 GROUP BY 键分区
-- 注意：分区数影响并行度和消费者数量
