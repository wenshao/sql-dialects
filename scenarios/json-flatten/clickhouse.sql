-- ClickHouse: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] ClickHouse Documentation - JSON Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/json-functions
--   [2] ClickHouse Documentation - JSONExtract
--       https://clickhouse.com/docs/en/sql-reference/functions/json-functions#jsonextract
--   [3] ClickHouse Documentation - JSON Object Type
--       https://clickhouse.com/docs/en/sql-reference/data-types/json

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   UInt32,
    data String
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO orders_json VALUES
(1, '{"customer": "Alice", "total": 150.00, "items": [{"product": "Widget", "qty": 2, "price": 25.00}, {"product": "Gadget", "qty": 1, "price": 100.00}], "address": {"city": "Beijing", "zip": "100000"}}'),
(2, '{"customer": "Bob", "total": 80.00, "items": [{"product": "Widget", "qty": 3, "price": 25.00}, {"product": "Doohickey", "qty": 1, "price": 5.00}], "address": {"city": "Shanghai", "zip": "200000"}}');

-- ============================================================
-- 1. 提取 JSON 字段为列 (JSONExtract)
-- ============================================================
SELECT id,
       JSONExtractString(data, 'customer')         AS customer,
       JSONExtractFloat(data, 'total')             AS total,
       JSONExtractString(data, 'address', 'city')  AS city,
       JSONExtractString(data, 'address', 'zip')   AS zip
FROM   orders_json;

-- ============================================================
-- 2. arrayJoin + JSONExtractArrayRaw 展开数组
-- ============================================================
SELECT id,
       JSONExtractString(data, 'customer')                  AS customer,
       JSONExtractString(item, 'product')                   AS product,
       JSONExtractUInt(item, 'qty')                         AS qty,
       JSONExtractFloat(item, 'price')                      AS price
FROM   orders_json
ARRAY JOIN JSONExtractArrayRaw(data, 'items') AS item;

-- ============================================================
-- 3. simpleJSONExtract 系列（高性能，适合简单 JSON）
-- ============================================================
SELECT id,
       simpleJSONExtractString(data, 'customer') AS customer,
       simpleJSONExtractFloat(data, 'total')     AS total
FROM   orders_json;

-- ============================================================
-- 4. JSON_VALUE / JSON_QUERY（ClickHouse 22.8+, SQL/JSON 标准语法）
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')        AS customer,
       JSON_QUERY(data, '$.items')           AS items_array
FROM   orders_json;

-- ============================================================
-- 5. JSON 对象类型（ClickHouse 实验性功能）
-- ============================================================
-- CREATE TABLE orders_json2 (
--     id   UInt32,
--     data JSON
-- ) ENGINE = MergeTree() ORDER BY id;
-- SELECT id, data.customer, data.address.city FROM orders_json2;
