-- TiDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TiDB Documentation - JSON Functions
--       https://docs.pingcap.com/tidb/stable/json-functions
--   [2] TiDB Documentation - JSON_TABLE (TiDB 6.5+)
--       https://docs.pingcap.com/tidb/stable/json-functions#json_table

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}'),
('{"customer":"Bob","total":80.0,"items":[{"product":"Widget","qty":3,"price":25.0},{"product":"Doohickey","qty":1,"price":5.0}],"address":{"city":"Shanghai","zip":"200000"}}');

-- ============================================================
-- 1. 提取 JSON 字段（兼容 MySQL 语法）
-- ============================================================
SELECT id,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.customer'))  AS customer,
       JSON_EXTRACT(data, '$.total')                    AS total,
       data->>'$.address.city'                          AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE（TiDB 6.5+）
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;

-- ============================================================
-- 3. 嵌套 JSON_TABLE
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               city     VARCHAR(100) PATH '$.address.city',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR(100) PATH '$.product',
                   qty     INT          PATH '$.qty'
               )
           )
       ) AS j;
