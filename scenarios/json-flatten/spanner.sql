-- Spanner: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Cloud Spanner - JSON Data Type
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#json_type
--   [2] Cloud Spanner - JSON Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/json_functions

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT64 NOT NULL,
    data JSON
) PRIMARY KEY (id);

-- ============================================================
-- 1. JSON_VALUE 提取字段
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')        AS customer,
       CAST(JSON_VALUE(data, '$.total') AS FLOAT64) AS total,
       JSON_VALUE(data, '$.address.city')    AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_QUERY_ARRAY + UNNEST 展开数组
-- ============================================================
SELECT o.id, JSON_VALUE(item, '$.product') AS product
FROM   orders_json o,
       UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item;
