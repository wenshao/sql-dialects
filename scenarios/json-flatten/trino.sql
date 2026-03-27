-- Trino: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Trino Documentation - JSON Functions
--       https://trino.io/docs/current/functions/json.html
--   [2] Trino Documentation - UNNEST
--       https://trino.io/docs/current/sql/select.html#unnest

-- ============================================================
-- 1. json_extract / json_extract_scalar 提取字段
-- ============================================================
SELECT id,
       json_extract_scalar(data, '$.customer')     AS customer,
       CAST(json_extract_scalar(data, '$.total') AS DOUBLE) AS total,
       json_extract_scalar(data, '$.address.city') AS city
FROM   orders_json;

-- ============================================================
-- 2. CAST 为 ARRAY + UNNEST 展开数组
-- ============================================================
SELECT o.id,
       json_extract_scalar(o.data, '$.customer') AS customer,
       json_extract_scalar(item, '$.product')    AS product,
       CAST(json_extract_scalar(item, '$.qty') AS INTEGER) AS qty
FROM   orders_json o
CROSS JOIN UNNEST(
    CAST(json_extract(o.data, '$.items') AS ARRAY(JSON))
) AS t(item);

-- ============================================================
-- 3. json_parse + CAST 转为 ROW / ARRAY<ROW>
-- ============================================================
SELECT o.id, items_row.product, items_row.qty
FROM   orders_json o
CROSS JOIN UNNEST(
    CAST(json_extract(o.data, '$.items')
         AS ARRAY(ROW(product VARCHAR, qty INTEGER, price DOUBLE)))
) AS t(items_row);
