-- ksqlDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] ksqlDB Documentation - TABLE
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table/
--   [2] ksqlDB Documentation - JOIN
--       https://docs.ksqldb.io/en/latest/developer-guide/joins/join-streams-and-tables/

-- ============================================================
-- ksqlDB 使用 TABLE 作为维度表（自动保留最新值）
-- ============================================================
CREATE TABLE dim_customer (
    customer_id VARCHAR PRIMARY KEY,
    name        VARCHAR,
    city        VARCHAR,
    tier        VARCHAR
) WITH (KAFKA_TOPIC = 'customer_topic', VALUE_FORMAT = 'JSON');

-- SCD Type 1: TABLE 本身就是 SCD Type 1（每个 key 保留最新值）
-- 新消息到达时自动覆盖旧值

-- Stream-Table Join（事实流关联维度表）
CREATE STREAM enriched_orders AS
SELECT o.order_id, o.amount, d.name, d.city, d.tier
FROM   orders_stream o
JOIN   dim_customer d ON o.customer_id = d.customer_id
EMIT CHANGES;

-- 注意: ksqlDB 不原生支持 SCD Type 2
-- 需要在上游系统处理版本化逻辑
