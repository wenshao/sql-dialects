-- Flink SQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Flink Documentation - JSON Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#json-functions
--   [2] Flink Documentation - JSON Format
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/formats/json/

-- ============================================================
-- 示例: 使用 JSON 格式的表
-- ============================================================
CREATE TABLE orders_json (
    customer STRING,
    total    DOUBLE,
    items    ARRAY<ROW<product STRING, qty INT, price DOUBLE>>,
    address  ROW<city STRING, zip STRING>
) WITH (
    'connector' = 'kafka',
    'format'    = 'json'
);

-- ============================================================
-- 1. 提取嵌套字段
-- ============================================================
SELECT customer, total, address.city, address.zip
FROM   orders_json;

-- ============================================================
-- 2. CROSS JOIN UNNEST 展开数组
-- ============================================================
SELECT o.customer, item.product, item.qty, item.price
FROM   orders_json o
CROSS JOIN UNNEST(o.items) AS item;

-- ============================================================
-- 3. JSON_VALUE / JSON_QUERY（Flink 1.15+, 字符串 JSON）
-- ============================================================
-- CREATE TABLE raw_json (data STRING) WITH (...);
-- SELECT JSON_VALUE(data, '$.customer') AS customer,
--        JSON_VALUE(data, '$.total' RETURNING DOUBLE) AS total
-- FROM raw_json;

-- ============================================================
-- 4. JSON_ARRAYAGG / JSON_OBJECTAGG（反向）
-- ============================================================
-- SELECT JSON_OBJECTAGG(KEY customer VALUE total) FROM orders_json;
