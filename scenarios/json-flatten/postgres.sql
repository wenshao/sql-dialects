-- PostgreSQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - JSON Functions
--       https://www.postgresql.org/docs/current/functions-json.html
--   [2] PostgreSQL Documentation - jsonb_array_elements
--       https://www.postgresql.org/docs/current/functions-json.html#FUNCTIONS-JSON-PROCESSING
--   [3] PostgreSQL Documentation - jsonb_each / jsonb_to_record
--       https://www.postgresql.org/docs/current/functions-json.html#FUNCTIONS-JSON-PROCESSING

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer": "Alice", "total": 150.00, "items": [
    {"product": "Widget", "qty": 2, "price": 25.00},
    {"product": "Gadget", "qty": 1, "price": 100.00}
  ],
  "address": {"city": "Beijing", "zip": "100000"}
}'),
('{"customer": "Bob", "total": 80.00, "items": [
    {"product": "Widget", "qty": 3, "price": 25.00},
    {"product": "Doohickey", "qty": 1, "price": 5.00}
  ],
  "address": {"city": "Shanghai", "zip": "200000"}
}');

-- ============================================================
-- 1. 提取 JSON 字段为列
-- ============================================================
SELECT id,
       data->>'customer'          AS customer,
       (data->>'total')::NUMERIC  AS total,
       data->'address'->>'city'   AS city,
       data->'address'->>'zip'    AS zip
FROM   orders_json;

-- ============================================================
-- 2. 展开 JSON 数组为多行 (jsonb_array_elements)
-- 适用版本: PostgreSQL 9.4+
-- ============================================================
SELECT o.id,
       o.data->>'customer'              AS customer,
       item->>'product'                  AS product,
       (item->>'qty')::INT               AS qty,
       (item->>'price')::NUMERIC         AS price
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;

-- ============================================================
-- 3. 展开 JSON 对象键值对 (jsonb_each)
-- ============================================================
SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data->'address') AS kv;

-- ============================================================
-- 4. jsonb_to_record / jsonb_to_recordset（转为关系记录）
-- 适用版本: PostgreSQL 9.4+
-- ============================================================
SELECT o.id, o.data->>'customer' AS customer, r.*
FROM   orders_json o,
       LATERAL jsonb_to_recordset(o.data->'items')
              AS r(product TEXT, qty INT, price NUMERIC);

-- ============================================================
-- 5. 嵌套 JSON 完全展平
-- ============================================================
SELECT o.id,
       o.data->>'customer'               AS customer,
       item->>'product'                   AS product,
       (item->>'qty')::INT                AS qty,
       o.data->'address'->>'city'         AS city
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;

-- ============================================================
-- 6. JSON 路径查询（PostgreSQL 12+, SQL/JSON 标准）
-- ============================================================
SELECT o.id,
       jsonb_path_query_first(o.data, '$.customer') AS customer,
       item.*
FROM   orders_json o,
       LATERAL jsonb_path_query(o.data, '$.items[*]') AS raw_item,
       LATERAL jsonb_to_record(raw_item)
              AS item(product TEXT, qty INT, price NUMERIC);
