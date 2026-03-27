-- SAP HANA: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] SAP HANA JSON Document Store
--       https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/ddd10cbe63c04ce48c3c882fec38faff.html
--   [2] SAP HANA SQL Reference - JSON Functions
--       https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/30f3c3dc14a5419ba459f5af9d5a8815.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data NCLOB
);

INSERT INTO orders_json (data) VALUES
('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}');

-- ============================================================
-- 1. JSON_VALUE 提取字段（SAP HANA 2.0 SPS03+）
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')          AS customer,
       JSON_VALUE(data, '$.total' RETURNING DECIMAL(10,2)) AS total,
       JSON_VALUE(data, '$.address.city')      AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE 展开数组（SAP HANA 2.0 SPS04+）
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               product NVARCHAR(100) PATH '$.product',
               qty     INT           PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;

-- ============================================================
-- 3. JSON_QUERY 提取子 JSON
-- ============================================================
SELECT id,
       JSON_QUERY(data, '$.items')     AS items_array,
       JSON_QUERY(data, '$.address')   AS address_obj
FROM   orders_json;
