-- CockroachDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] CockroachDB Documentation - JSONB Functions
--       https://www.cockroachlabs.com/docs/stable/jsonb
--   [2] CockroachDB Documentation - jsonb_array_elements
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators#jsonb-functions

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}'),
('{"customer":"Bob","total":80.0,"items":[{"product":"Widget","qty":3,"price":25.0},{"product":"Doohickey","qty":1,"price":5.0}],"address":{"city":"Shanghai","zip":"200000"}}');

-- ============================================================
-- 1. 提取 JSON 字段（兼容 PostgreSQL）
-- ============================================================
SELECT id,
       data->>'customer'          AS customer,
       (data->>'total')::NUMERIC  AS total,
       data->'address'->>'city'   AS city
FROM   orders_json;

-- ============================================================
-- 2. jsonb_array_elements 展开数组
-- ============================================================
SELECT o.id,
       o.data->>'customer'        AS customer,
       item->>'product'           AS product,
       (item->>'qty')::INT        AS qty,
       (item->>'price')::NUMERIC  AS price
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;

-- ============================================================
-- 3. jsonb_each 展开对象
-- ============================================================
SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data) AS kv;
