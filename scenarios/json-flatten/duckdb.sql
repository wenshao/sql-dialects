-- DuckDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] DuckDB Documentation - JSON Functions
--       https://duckdb.org/docs/extensions/json.html
--   [2] DuckDB Documentation - UNNEST
--       https://duckdb.org/docs/sql/query_syntax/unnest

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json AS
SELECT 1 AS id, '{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}'::JSON AS data
UNION ALL
SELECT 2, '{"customer":"Bob","total":80.0,"items":[{"product":"Widget","qty":3,"price":25.0},{"product":"Doohickey","qty":1,"price":5.0}],"address":{"city":"Shanghai","zip":"200000"}}'::JSON;

-- ============================================================
-- 1. 提取 JSON 字段（箭头语法）
-- ============================================================
SELECT id,
       data->>'customer'         AS customer,
       (data->>'total')::DOUBLE  AS total,
       data->'address'->>'city'  AS city
FROM   orders_json;

-- ============================================================
-- 2. json_extract + UNNEST 展开数组
-- ============================================================
SELECT o.id,
       o.data->>'customer'        AS customer,
       item->>'product'           AS product,
       (item->>'qty')::INT        AS qty,
       (item->>'price')::DOUBLE   AS price
FROM   orders_json o,
       UNNEST(json_extract(o.data, '$.items')::JSON[]) AS t(item);

-- ============================================================
-- 3. json_keys / json_each
-- ============================================================
SELECT o.id, kv.*
FROM   orders_json o,
       LATERAL (SELECT UNNEST(json_keys(o.data)) AS key);

-- ============================================================
-- 4. 直接读取 JSON 文件
-- ============================================================
-- SELECT * FROM read_json_auto('orders.json');
-- SELECT * FROM read_json('orders.json',
--     columns = {customer: 'VARCHAR', total: 'DOUBLE'});
