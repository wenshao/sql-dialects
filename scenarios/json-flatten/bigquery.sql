-- BigQuery: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] BigQuery SQL Reference - JSON Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions
--   [2] BigQuery SQL Reference - UNNEST
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest
--   [3] BigQuery SQL Reference - JSON Data Type
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#json_type

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TEMP TABLE orders_json AS
SELECT 1 AS id, JSON '{"customer": "Alice", "total": 150.00,
  "items": [{"product": "Widget", "qty": 2, "price": 25.00},
             {"product": "Gadget", "qty": 1, "price": 100.00}],
  "address": {"city": "Beijing", "zip": "100000"}}' AS data
UNION ALL
SELECT 2, JSON '{"customer": "Bob", "total": 80.00,
  "items": [{"product": "Widget", "qty": 3, "price": 25.00},
             {"product": "Doohickey", "qty": 1, "price": 5.00}],
  "address": {"city": "Shanghai", "zip": "200000"}}';

-- ============================================================
-- 1. 提取 JSON 字段为列
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')                    AS customer,
       CAST(JSON_VALUE(data, '$.total') AS FLOAT64)      AS total,
       JSON_VALUE(data, '$.address.city')                AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_QUERY_ARRAY + UNNEST 展开数组
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer')     AS customer,
       JSON_VALUE(item, '$.product')        AS product,
       CAST(JSON_VALUE(item, '$.qty') AS INT64) AS qty,
       CAST(JSON_VALUE(item, '$.price') AS FLOAT64) AS price
FROM   orders_json o,
       UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item;

-- ============================================================
-- 3. STRUCT + ARRAY 原生类型展平（如果数据已用原生类型存储）
-- ============================================================
-- CREATE TEMP TABLE orders_native AS
-- SELECT 1 AS id, 'Alice' AS customer,
--        [STRUCT('Widget' AS product, 2 AS qty, 25.0 AS price),
--         STRUCT('Gadget', 1, 100.0)] AS items;
-- SELECT o.id, o.customer, item.product, item.qty
-- FROM orders_native o, UNNEST(o.items) AS item;

-- ============================================================
-- 4. 带序号的数组展开
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer') AS customer,
       pos,
       JSON_VALUE(item, '$.product')    AS product
FROM   orders_json o,
       UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item WITH OFFSET AS pos;
