-- ksqlDB: UPDATE
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- ksqlDB 不支持 UPDATE 语句
-- 数据更新通过其他机制实现

-- ============================================================
-- TABLE 更新（通过 INSERT 覆盖）
-- ============================================================

-- TABLE 基于 PRIMARY KEY 的 changelog 语义
-- 插入相同 PRIMARY KEY 的新记录覆盖旧值

-- 原始数据
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice@example.com', 'US');

-- "更新"：插入相同 PRIMARY KEY 的新记录
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice_new@example.com', 'EU');
-- user_123 现在的 email 是 alice_new@example.com

-- ============================================================
-- STREAM 不支持更新
-- ============================================================

-- STREAM 是不可变的追加流（append-only）
-- 每条记录都是独立的事件，不能修改

-- ============================================================
-- 通过派生 STREAM/TABLE 实现"转换"
-- ============================================================

-- 转换 STREAM 中的数据（创建新 STREAM）
CREATE STREAM transformed_events AS
SELECT event_id,
       UCASE(event_type) AS event_type,    -- 转换大写
       payload,
       ROWTIME AS event_time
FROM events
EMIT CHANGES;

-- 过滤后重新聚合
CREATE TABLE updated_totals AS
SELECT user_id,
       SUM(CASE WHEN status = 'valid' THEN amount ELSE 0 END) AS valid_total
FROM orders
GROUP BY user_id
EMIT CHANGES;

-- ============================================================
-- 删除 TABLE 中的记录（发送 NULL 值 tombstone）
-- ============================================================

-- 在 Kafka 中发送 NULL value 的消息实现删除
-- 这需要通过 Kafka Producer API 完成，不是 ksqlDB SQL

-- 注意：ksqlDB 不支持 UPDATE 语句
-- 注意：TABLE 通过插入相同 KEY 的新记录实现更新
-- 注意：STREAM 是不可变的，不能更新或删除
-- 注意：数据修改主要通过上游 Kafka Producer 完成
