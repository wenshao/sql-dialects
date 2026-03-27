-- ksqlDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] ksqlDB Documentation - JSON Format
--       https://docs.ksqldb.io/en/latest/reference/serialization/#json
--   [2] ksqlDB Documentation - EXTRACTJSONFIELD
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/#extractjsonfield

-- ============================================================
-- ksqlDB 原生支持 JSON 格式，schema 在建流/表时定义
-- ============================================================
CREATE STREAM orders_stream (
    customer VARCHAR,
    total    DOUBLE,
    items    ARRAY<STRUCT<product VARCHAR, qty INT, price DOUBLE>>,
    address  STRUCT<city VARCHAR, zip VARCHAR>
) WITH (
    KAFKA_TOPIC = 'orders_topic',
    VALUE_FORMAT = 'JSON'
);

-- ============================================================
-- 1. 提取嵌套字段
-- ============================================================
SELECT customer, total, address->city, address->zip
FROM   orders_stream
EMIT CHANGES;

-- ============================================================
-- 2. EXPLODE 展开数组
-- ============================================================
SELECT customer,
       EXPLODE(items)->product AS product,
       EXPLODE(items)->qty     AS qty
FROM   orders_stream
EMIT CHANGES;

-- ============================================================
-- 3. EXTRACTJSONFIELD（字符串 JSON）
-- ============================================================
-- CREATE STREAM raw_stream (data VARCHAR) WITH (...);
-- SELECT EXTRACTJSONFIELD(data, '$.customer') AS customer
-- FROM raw_stream EMIT CHANGES;
