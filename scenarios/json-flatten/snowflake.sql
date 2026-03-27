-- Snowflake: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - FLATTEN
--       https://docs.snowflake.com/en/sql-reference/functions/flatten
--   [2] Snowflake SQL Reference - Semi-structured Data
--       https://docs.snowflake.com/en/user-guide/semistructured-concepts
--   [3] Snowflake SQL Reference - PARSE_JSON
--       https://docs.snowflake.com/en/sql-reference/functions/parse_json

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY TABLE orders_json (
    id   NUMBER AUTOINCREMENT,
    data VARIANT NOT NULL
);

INSERT INTO orders_json (data)
SELECT PARSE_JSON('{
  "customer": "Alice", "total": 150.00,
  "items": [{"product": "Widget", "qty": 2, "price": 25.00},
             {"product": "Gadget", "qty": 1, "price": 100.00}],
  "address": {"city": "Beijing", "zip": "100000"}
}');
INSERT INTO orders_json (data)
SELECT PARSE_JSON('{
  "customer": "Bob", "total": 80.00,
  "items": [{"product": "Widget", "qty": 3, "price": 25.00},
             {"product": "Doohickey", "qty": 1, "price": 5.00}],
  "address": {"city": "Shanghai", "zip": "200000"}
}');

-- ============================================================
-- 1. 提取 JSON 字段为列（冒号语法）
-- ============================================================
SELECT id,
       data:customer::VARCHAR        AS customer,
       data:total::NUMBER(10,2)      AS total,
       data:address.city::VARCHAR    AS city,
       data:address.zip::VARCHAR     AS zip
FROM   orders_json;

-- ============================================================
-- 2. FLATTEN 展开数组（推荐）
-- ============================================================
SELECT o.id,
       o.data:customer::VARCHAR          AS customer,
       f.VALUE:product::VARCHAR          AS product,
       f.VALUE:qty::INT                  AS qty,
       f.VALUE:price::NUMBER(10,2)       AS price,
       f.INDEX                           AS item_index
FROM   orders_json o,
       LATERAL FLATTEN(INPUT => o.data:items) f;

-- ============================================================
-- 3. FLATTEN 展开对象
-- ============================================================
SELECT o.id,
       f.KEY    AS field_name,
       f.VALUE  AS field_value
FROM   orders_json o,
       LATERAL FLATTEN(INPUT => o.data:address) f;

-- ============================================================
-- 4. 递归 FLATTEN（嵌套展平）
-- ============================================================
SELECT o.id,
       f.KEY, f.PATH, f.VALUE
FROM   orders_json o,
       LATERAL FLATTEN(INPUT => o.data, RECURSIVE => TRUE) f
WHERE  f.VALUE IS NOT NULL
  AND  TYPEOF(f.VALUE) NOT IN ('OBJECT', 'ARRAY');

-- ============================================================
-- 5. GET_PATH / GET 动态路径
-- ============================================================
SELECT id,
       GET_PATH(data, 'customer')           AS customer,
       GET_PATH(data, 'items[0].product')   AS first_product
FROM   orders_json;
