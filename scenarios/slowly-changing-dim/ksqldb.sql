-- ksqlDB: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] ksqlDB Documentation - CREATE TABLE
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-table/
--   [2] ksqlDB Documentation - CREATE STREAM
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-stream/
--   [3] ksqlDB Documentation - JOIN Streams and Tables
--       https://docs.ksqldb.io/en/latest/developer-guide/joins/join-streams-and-tables/
--   [4] ksqlDB Documentation - AS SELECT (Materialized View)
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-stream-as/

-- ============================================================
-- 1. 维度表定义（TABLE = 最新状态，天然 SCD Type 1）
-- ============================================================

-- ksqlDB 的 TABLE 基于 Kafka changelog topic，自动保留每个 key 的最新值
CREATE TABLE dim_customer (
    customer_id VARCHAR PRIMARY KEY,
    name        VARCHAR,
    city        VARCHAR,
    tier        VARCHAR
) WITH (
    KAFKA_TOPIC  = 'customer_topic',
    VALUE_FORMAT = 'JSON'
);

-- 源数据流（流式输入）
CREATE STREAM stg_customer_stream (
    customer_id VARCHAR KEY,
    name        VARCHAR,
    city        VARCHAR,
    tier        VARCHAR
) WITH (
    KAFKA_TOPIC  = 'stg_customer_topic',
    VALUE_FORMAT = 'JSON'
);

-- ============================================================
-- 2. 样本数据（通过 INSERT 模拟）
-- ============================================================

INSERT INTO dim_customer (customer_id, name, city, tier) VALUES ('C001', 'Alice', 'Shanghai', 'Gold');
INSERT INTO dim_customer (customer_id, name, city, tier) VALUES ('C002', 'Bob', 'Beijing', 'Silver');
INSERT INTO dim_customer (customer_id, name, city, tier) VALUES ('C003', 'Charlie', 'Shenzhen', 'Bronze');

-- ============================================================
-- 3. SCD Type 1: TABLE 自动实现
-- ============================================================

-- ksqlDB 的 TABLE 本身就是 SCD Type 1 的实现
-- 当新消息到达时，相同 key 的记录自动覆盖旧值
-- 无需编写 MERGE 或 UPDATE 语句

-- 将流数据持续写入维度表（等同于持续 MERGE）
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer_stream
EMIT CHANGES;

-- ============================================================
-- 4. SCD Type 2: 模拟历史版本（ksqlDB 不原生支持）
-- ============================================================

-- ksqlDB 不原生支持 SCD Type 2，需要手动实现版本化逻辑
-- 方案: 使用 Stream + 时间窗口模拟历史版本

-- 创建版本化事件流
CREATE STREAM customer_version_events (
    customer_id VARCHAR KEY,
    name        VARCHAR,
    city        VARCHAR,
    tier        VARCHAR,
    version     INT,
    effective_ts VARCHAR
) WITH (
    KAFKA_TOPIC  = 'customer_versions',
    VALUE_FORMAT = 'JSON'
);

-- 创建事实流（订单）
CREATE STREAM orders_stream (
    order_id    VARCHAR KEY,
    customer_id VARCHAR,
    amount      DECIMAL(10, 2)
) WITH (
    KAFKA_TOPIC  = 'orders_topic',
    VALUE_FORMAT = 'JSON'
);

-- ============================================================
-- 5. Stream-Table Join（事实流关联维度表）
-- ============================================================

-- 实时关联: 订单流关联客户维度表（获取最新维度属性）
CREATE STREAM enriched_orders AS
SELECT o.order_id, o.amount,
       d.name AS customer_name, d.city, d.tier
FROM   orders_stream o
INNER JOIN dim_customer d ON o.customer_id = d.customer_id
EMIT CHANGES;

-- 聚合查询: 按客户等级统计订单总金额
CREATE TABLE order_summary_by_tier AS
SELECT d.tier,
       COUNT(o.order_id) AS order_count,
       SUM(o.amount)     AS total_amount
FROM   orders_stream o
INNER JOIN dim_customer d ON o.customer_id = d.customer_id
GROUP BY d.tier
EMIT CHANGES;

-- ============================================================
-- 6. 查询示例
-- ============================================================

-- 查询维度表当前状态（pull query，最新快照）
SELECT customer_id, name, city, tier FROM dim_customer WHERE customer_id = 'C001';

-- 查询所有客户（push query，持续输出变更）
SELECT customer_id, name, city, tier FROM dim_customer EMIT CHANGES;

-- ============================================================
-- 7. ksqlDB 注意事项与最佳实践
-- ============================================================

-- 1. ksqlDB 的 TABLE 自动实现 SCD Type 1: 每个 key 只保留最新值
-- 2. ksqlDB 不原生支持 SCD Type 2（版本化历史），需要在上游系统处理
-- 3. SCD Type 2 替代方案:
--    (a) 使用 Kafka Streams 的 Versioned KTable（Kafka 3.5+）
--    (b) 在上游 Debezium/Connect 中实现版本化
--    (c) 使用 Confluent Tableflow (2024+)
-- 4. Stream-Table JOIN 使用实时维度快照，不保留历史
-- 5. EMIT CHANGES 将查询变为持续推送模式（push query）
-- 6. PRIMARY KEY 定义在 TABLE 中是必须的，对应 Kafka 消息的 key
-- 7. 对于需要历史版本追溯的场景，建议使用 Debezium + 数据仓库组合
-- 8. VALUE_FORMAT = 'JSON' 适合开发，生产推荐 'AVRO' 以获得更好的性能和 schema 演进能力
