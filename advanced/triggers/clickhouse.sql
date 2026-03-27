-- ClickHouse: 触发器
--
-- 参考资料:
--   [1] ClickHouse - Materialized Views
--       https://clickhouse.com/docs/en/sql-reference/statements/create/view#materialized-view
--   [2] ClickHouse - Table Engines
--       https://clickhouse.com/docs/en/engines/table-engines

-- ClickHouse 不支持传统触发器
-- 使用物化视图和其他机制替代

-- ============================================================
-- 替代方案 1: 物化视图（最接近触发器的功能）
-- ============================================================

-- 物化视图在 INSERT 时自动触发计算
-- 类似 AFTER INSERT 触发器

-- 汇总聚合（SummingMergeTree）
CREATE MATERIALIZED VIEW mv_daily_summary
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (date, user_id)
AS
SELECT
    toDate(order_date) AS date,
    user_id,
    sum(amount) AS total,
    count() AS cnt
FROM orders
GROUP BY date, user_id;

-- 每次 INSERT INTO orders，mv_daily_summary 自动增量更新

-- 去重（ReplacingMergeTree）
CREATE MATERIALIZED VIEW mv_latest_users
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY id
AS
SELECT id, username, email, updated_at
FROM users;

-- 数据转换
CREATE MATERIALIZED VIEW mv_parsed_logs
ENGINE = MergeTree()
ORDER BY timestamp
AS
SELECT
    timestamp,
    extractURLParameter(url, 'utm_source') AS utm_source,
    toDate(timestamp) AS date
FROM raw_logs;

-- ============================================================
-- 替代方案 2: 物化视图链（多级触发器）
-- ============================================================

-- 第一级：从原始表到中间表
CREATE MATERIALIZED VIEW mv_step1
ENGINE = MergeTree() ORDER BY user_id AS
SELECT user_id, count() AS daily_count, toDate(timestamp) AS date
FROM events GROUP BY user_id, date;

-- 第二级：从中间表到最终表
CREATE MATERIALIZED VIEW mv_step2
ENGINE = SummingMergeTree() ORDER BY user_id AS
SELECT user_id, sum(daily_count) AS total_count
FROM mv_step1 GROUP BY user_id;

-- 数据流: events -> mv_step1 -> mv_step2

-- ============================================================
-- 替代方案 3: TTL（自动数据过期和移动）
-- ============================================================

-- 类似定时触发器，自动执行数据过期和层级存储
CREATE TABLE logs (
    timestamp DateTime,
    level     String,
    message   String
)
ENGINE = MergeTree()
ORDER BY timestamp
TTL timestamp + INTERVAL 7 DAY DELETE,
    timestamp + INTERVAL 1 DAY TO VOLUME 'cold_storage';

-- 7 天后自动删除
-- 1 天后自动移动到冷存储

-- ============================================================
-- 替代方案 4: Mutation（异步修改）
-- ============================================================

-- 类似触发器的批量更新操作（但是异步的）
ALTER TABLE users UPDATE status = 0
WHERE last_login < now() - INTERVAL 90 DAY;

ALTER TABLE orders DELETE WHERE status = 'cancelled' AND order_date < '2023-01-01';

-- 查看 mutation 进度
SELECT * FROM system.mutations WHERE table = 'users' AND is_done = 0;

-- ============================================================
-- 替代方案 5: 外部编排（Kafka + 物化视图）
-- ============================================================

-- 使用 Kafka Engine 消费消息流
CREATE TABLE kafka_events (
    timestamp DateTime,
    user_id   UInt64,
    event     String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'events',
    kafka_group_name = 'clickhouse',
    kafka_format = 'JSONEachRow';

-- 物化视图自动消费 Kafka 数据并写入目标表
CREATE MATERIALIZED VIEW mv_kafka_consumer TO events AS
SELECT * FROM kafka_events;

-- 数据从 Kafka 进入 -> 物化视图自动处理 -> 写入目标表

-- 注意：ClickHouse 不支持行级触发器
-- 注意：物化视图是最主要的替代方案，在 INSERT 时自动触发
-- 注意：物化视图不会被 UPDATE/DELETE/MERGE 触发
-- 注意：TTL 提供自动数据生命周期管理
-- 注意：Kafka Engine + 物化视图实现实时数据管道
