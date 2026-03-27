-- ksqlDB: UPSERT
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- ksqlDB TABLE 天然具有 UPSERT 语义
-- 相同 PRIMARY KEY 的 INSERT 自动覆盖旧值

-- ============================================================
-- TABLE 的隐式 UPSERT（通过 PRIMARY KEY 覆盖）
-- ============================================================

-- 创建 TABLE
CREATE TABLE users (
    user_id    VARCHAR PRIMARY KEY,
    username   VARCHAR,
    email      VARCHAR,
    region     VARCHAR
) WITH (
    KAFKA_TOPIC = 'users_topic',
    VALUE_FORMAT = 'JSON'
);

-- 第一次插入
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice@example.com', 'US');

-- 相同 PRIMARY KEY 再次插入 → 自动覆盖（UPSERT 语义）
INSERT INTO users (user_id, username, email, region)
VALUES ('user_123', 'alice', 'alice_new@example.com', 'EU');
-- user_123 的数据被更新

-- ============================================================
-- 聚合 TABLE 的 UPSERT（通过 GROUP BY 键）
-- ============================================================

-- 创建聚合 TABLE（GROUP BY 键即为 PRIMARY KEY）
CREATE TABLE user_totals AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount
FROM orders
GROUP BY user_id
EMIT CHANGES;

-- 每当 orders STREAM 收到新数据，user_totals 自动更新
-- GROUP BY 键（user_id）相同的记录自动 UPSERT

-- ============================================================
-- STREAM 不支持 UPSERT
-- ============================================================

-- STREAM 是追加流，每条记录独立，不存在覆盖
-- 相同 KEY 的多条记录都会保留

CREATE STREAM pageviews (
    user_id VARCHAR KEY,
    page_url VARCHAR
) WITH (
    KAFKA_TOPIC = 'pageviews_topic',
    VALUE_FORMAT = 'JSON'
);

-- 每次 INSERT 都追加，不会覆盖
INSERT INTO pageviews (user_id, page_url) VALUES ('user_123', '/page1');
INSERT INTO pageviews (user_id, page_url) VALUES ('user_123', '/page2');
-- 两条记录都保留

-- 注意：TABLE 的 INSERT 天然是 UPSERT（changelog 语义）
-- 注意：STREAM 的 INSERT 是追加（append-only 语义）
-- 注意：不需要 ON CONFLICT 或 MERGE 语法
-- 注意：TABLE 中删除需要通过 Kafka tombstone 消息
-- 注意：聚合 TABLE 由持久查询自动维护
