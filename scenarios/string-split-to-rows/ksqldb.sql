-- ksqlDB: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] ksqlDB Documentation - SPLIT
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/#split
--   [2] ksqlDB Documentation - EXPLODE
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/table-functions/#explode

-- ============================================================
-- 示例数据（流）
-- ============================================================
CREATE STREAM tags_stream (
    id   INT KEY,
    name VARCHAR,
    tags VARCHAR
) WITH (
    KAFKA_TOPIC = 'tags_topic',
    VALUE_FORMAT = 'JSON'
);

-- ============================================================
-- 方法 1: EXPLODE + SPLIT（推荐）
-- ============================================================
SELECT id, name, EXPLODE(SPLIT(tags, ',')) AS tag
FROM   tags_stream
EMIT CHANGES;

-- ============================================================
-- 注意: ksqlDB 是流处理引擎，查询结果持续输出
-- EXPLODE 会将数组中每个元素生成一条独立的消息
-- ============================================================
