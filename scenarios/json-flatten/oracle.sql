-- Oracle: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Oracle Documentation - JSON_TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/JSON_TABLE.html
--   [2] Oracle Documentation - JSON_VALUE / JSON_QUERY
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/JSON_VALUE.html
--   [3] Oracle 21c - JSON Data Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/adjsn/

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data CLOB CONSTRAINT check_json CHECK (data IS JSON)  -- Oracle 12c+
    -- Oracle 21c+ 可直接用 JSON 类型: data JSON
);

INSERT INTO orders_json (data) VALUES
('{"customer": "Alice", "total": 150.00, "items": [
    {"product": "Widget", "qty": 2, "price": 25.00},
    {"product": "Gadget", "qty": 1, "price": 100.00}
  ],
  "address": {"city": "Beijing", "zip": "100000"}
}');
INSERT INTO orders_json (data) VALUES
('{"customer": "Bob", "total": 80.00, "items": [
    {"product": "Widget", "qty": 3, "price": 25.00},
    {"product": "Doohickey", "qty": 1, "price": 5.00}
  ],
  "address": {"city": "Shanghai", "zip": "200000"}
}');
COMMIT;

-- ============================================================
-- 1. 提取 JSON 字段为列 (JSON_VALUE)
-- 适用版本: Oracle 12c+
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')         AS customer,
       JSON_VALUE(data, '$.total' RETURNING NUMBER) AS total,
       JSON_VALUE(data, '$.address.city')     AS city,
       JSON_VALUE(data, '$.address.zip')      AS zip
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE 展开数组为多行（推荐, Oracle 12c+）
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               rownum  FOR ORDINALITY,
               product VARCHAR2(100) PATH '$.product',
               qty     NUMBER        PATH '$.qty',
               price   NUMBER(10,2)  PATH '$.price'
           )
       ) j;

-- ============================================================
-- 3. 嵌套 JSON_TABLE（完全展平）
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$'
           COLUMNS (
               customer VARCHAR2(100) PATH '$.customer',
               city     VARCHAR2(100) PATH '$.address.city',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR2(100) PATH '$.product',
                   qty     NUMBER        PATH '$.qty',
                   price   NUMBER(10,2)  PATH '$.price'
               )
           )
       ) j;

-- ============================================================
-- 4. JSON_QUERY 提取子 JSON
-- ============================================================
SELECT id,
       JSON_QUERY(data, '$.items')            AS items_array,
       JSON_QUERY(data, '$.address')          AS address_obj
FROM   orders_json;

-- ============================================================
-- 5. JSON_EXISTS 条件过滤
-- ============================================================
SELECT id, JSON_VALUE(data, '$.customer') AS customer
FROM   orders_json
WHERE  JSON_EXISTS(data, '$.items[*]?(@.price > 50)');

-- ============================================================
-- 6. 简化点语法（Oracle 12c+，需要 IS JSON 约束）
-- ============================================================
SELECT o.id,
       o.data.customer,
       o.data.address.city
FROM   orders_json o;
