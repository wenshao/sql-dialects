-- SQLite: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] SQLite Documentation - JSON1 Extension
--       https://www.sqlite.org/json1.html
--   [2] SQLite Documentation - json_each / json_tree
--       https://www.sqlite.org/json1.html#jeach

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    data TEXT NOT NULL
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
-- 1. 提取 JSON 字段为列 (json_extract)
-- 适用版本: SQLite 3.9.0+ (JSON1 扩展)
-- ============================================================
SELECT id,
       json_extract(data, '$.customer')      AS customer,
       json_extract(data, '$.total')         AS total,
       json_extract(data, '$.address.city')  AS city,
       json_extract(data, '$.address.zip')   AS zip
FROM   orders_json;

-- 简写语法（SQLite 3.38.0+）
SELECT id,
       data->>'$.customer'    AS customer,
       data->>'$.total'       AS total,
       data->>'$.address.city' AS city
FROM   orders_json;

-- ============================================================
-- 2. json_each 展开数组为多行
-- ============================================================
SELECT o.id,
       json_extract(o.data, '$.customer')       AS customer,
       json_extract(j.value, '$.product')       AS product,
       json_extract(j.value, '$.qty')           AS qty,
       json_extract(j.value, '$.price')         AS price
FROM   orders_json o,
       json_each(o.data, '$.items') j;

-- ============================================================
-- 3. json_each 展开对象键值对
-- ============================================================
SELECT o.id, j.key, j.value, j.type
FROM   orders_json o,
       json_each(o.data) j;

-- ============================================================
-- 4. json_tree 递归展平（完全展开所有嵌套层）
-- ============================================================
SELECT o.id, t.fullkey, t.key, t.value, t.type, t.atom
FROM   orders_json o,
       json_tree(o.data) t
WHERE  t.atom IS NOT NULL;    -- 只保留叶子节点

-- ============================================================
-- 5. json_group_array / json_group_object（反向：行转 JSON）
-- ============================================================
-- SELECT json_group_array(json_object('id', id, 'customer',
--        json_extract(data, '$.customer')))
-- FROM orders_json;
