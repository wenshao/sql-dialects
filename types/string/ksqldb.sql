-- ksqlDB: 字符串类型
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/
--   [2] ksqlDB API Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/api/

-- VARCHAR / STRING: 唯一的字符串类型

CREATE STREAM events (
    event_id   VARCHAR KEY,
    event_type VARCHAR,
    message    VARCHAR,
    payload    VARCHAR                    -- JSON 也存为 VARCHAR
) WITH (
    KAFKA_TOPIC = 'events_topic',
    VALUE_FORMAT = 'JSON'
);

-- 注意：VARCHAR 和 STRING 是同义词

-- ============================================================
-- 字符串函数
-- ============================================================

-- 拼接
SELECT CONCAT(event_type, ':', event_id) FROM events EMIT CHANGES;

-- 大小写
SELECT UCASE(event_type) FROM events EMIT CHANGES;
SELECT LCASE(event_type) FROM events EMIT CHANGES;

-- 截取
SELECT SUBSTRING(message, 1, 10) FROM events EMIT CHANGES;

-- 长度
SELECT LEN(message) FROM events EMIT CHANGES;

-- 去空格
SELECT TRIM(message) FROM events EMIT CHANGES;

-- 查找
SELECT INSTR(message, 'error') FROM events EMIT CHANGES;

-- 替换
SELECT REPLACE(message, 'error', 'warning') FROM events EMIT CHANGES;

-- 分割
SELECT SPLIT(message, ',') FROM events EMIT CHANGES;  -- 返回 ARRAY

-- ============================================================
-- 字符串与其他类型转换
-- ============================================================

SELECT CAST(123 AS VARCHAR) FROM events EMIT CHANGES;
SELECT CAST('123' AS INT) FROM events EMIT CHANGES;
SELECT CAST('3.14' AS DOUBLE) FROM events EMIT CHANGES;

-- ============================================================
-- JSON 字符串处理
-- ============================================================

-- 从 VARCHAR 中提取 JSON 字段
SELECT EXTRACTJSONFIELD(payload, '$.name') AS name FROM events EMIT CHANGES;
SELECT EXTRACTJSONFIELD(payload, '$.items[0].id') AS item_id FROM events EMIT CHANGES;

-- 注意：VARCHAR 是唯一的字符串类型
-- 注意：没有 CHAR(n) / TEXT / CLOB
-- 注意：VARCHAR 没有长度限制
-- 注意：JSON 数据以 VARCHAR 形式存储和处理
-- 注意：不支持 COLLATION 和字符集设置
