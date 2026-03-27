-- ksqlDB: 临时表与临时存储
--
-- 参考资料:
--   [1] ksqlDB Documentation - CREATE STREAM / TABLE
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/create-stream/

-- ksqlDB 不支持传统临时表
-- 使用 STREAM 和 TABLE 作为持久化的数据抽象

-- ============================================================
-- 创建派生流/表（替代临时表）
-- ============================================================

-- 创建过滤后的流
CREATE STREAM active_user_events AS
SELECT * FROM user_events
WHERE event_type = 'active'
EMIT CHANGES;

-- 创建聚合表
CREATE TABLE user_counts AS
SELECT user_id, COUNT(*) AS event_count
FROM user_events
GROUP BY user_id
EMIT CHANGES;

-- ============================================================
-- Pull 查询（类似临时查询）
-- ============================================================

-- 点查询（不持久化）
SELECT * FROM user_counts WHERE user_id = 'user123';

-- 范围查询
SELECT * FROM user_counts WHERE event_count > 100;

-- ============================================================
-- 临时查询（Push Query）
-- ============================================================

-- Push 查询持续输出结果
SELECT * FROM user_events WHERE amount > 1000 EMIT CHANGES;

-- 注意：ksqlDB 是流处理引擎，没有临时表概念
-- 注意：所有 STREAM 和 TABLE 都由 Kafka Topic 支持
-- 注意：Pull 查询提供即时的点查询能力
-- 注意：Push 查询提供持续的流式结果
