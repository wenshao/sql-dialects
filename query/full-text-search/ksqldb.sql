-- ksqlDB: 全文搜索
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- ksqlDB 不支持全文搜索
-- 仅提供基本的字符串匹配功能

-- ============================================================
-- LIKE 模糊搜索
-- ============================================================

-- 基本 LIKE
CREATE STREAM error_events AS
SELECT * FROM events WHERE payload LIKE '%error%'
EMIT CHANGES;

-- 前缀匹配
CREATE STREAM api_events AS
SELECT * FROM events WHERE event_type LIKE 'api_%'
EMIT CHANGES;

-- ============================================================
-- 字符串函数辅助搜索
-- ============================================================

-- INSTR（查找子字符串位置）
CREATE STREAM matched_events AS
SELECT * FROM events WHERE INSTR(payload, 'error') > 0
EMIT CHANGES;

-- UCASE/LCASE 不敏感搜索
CREATE STREAM case_insensitive AS
SELECT * FROM events WHERE LCASE(payload) LIKE '%error%'
EMIT CHANGES;

-- SUBSTRING 提取
SELECT event_id,
    SUBSTRING(payload, INSTR(payload, 'error'), 20) AS context
FROM events
WHERE INSTR(payload, 'error') > 0
EMIT CHANGES;

-- ============================================================
-- 正则表达式（不支持）
-- ============================================================

-- ksqlDB 不支持 REGEXP / RLIKE

-- ============================================================
-- 替代方案
-- ============================================================

-- 方案 1：在 Kafka Connect 中使用 SMT 过滤
-- 方案 2：在上游生产者中打标签

-- 使用 STRUCT 字段预处理搜索
CREATE STREAM tagged_events (
    event_id   VARCHAR KEY,
    payload    VARCHAR,
    tags       ARRAY<VARCHAR>       -- 预提取的关键词标签
) WITH (
    KAFKA_TOPIC = 'tagged_events',
    VALUE_FORMAT = 'JSON'
);

-- 基于标签过滤（替代全文搜索）
CREATE STREAM error_tagged AS
SELECT * FROM tagged_events WHERE ARRAY_CONTAINS(tags, 'error')
EMIT CHANGES;

-- 方案 3：将数据导出到 Elasticsearch
-- 通过 Kafka Connect Elasticsearch Sink Connector

-- 注意：ksqlDB 不支持全文搜索
-- 注意：仅支持 LIKE 和基本字符串函数
-- 注意：不支持正则表达式
-- 注意：全文搜索建议使用 Elasticsearch + Kafka Connect
