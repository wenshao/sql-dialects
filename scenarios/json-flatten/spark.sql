-- Spark SQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Spark SQL Reference - from_json / get_json_object
--       https://spark.apache.org/docs/latest/api/sql/index.html#from_json
--   [2] Spark SQL Reference - explode / inline
--       https://spark.apache.org/docs/latest/api/sql/index.html#explode
--   [3] Spark SQL Reference - JSON Data Source
--       https://spark.apache.org/docs/latest/sql-data-sources-json.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY VIEW orders_json AS
SELECT 1 AS id, '{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}' AS data;

-- ============================================================
-- 1. get_json_object 提取字段
-- ============================================================
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.total')         AS total,
       get_json_object(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. from_json + schema 转为结构化类型（推荐, Spark 2.1+）
-- ============================================================
SELECT id,
       parsed.customer,
       parsed.total,
       parsed.address.city AS city
FROM (
    SELECT id,
           from_json(data,
               'customer STRING, total DOUBLE, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>, address STRUCT<city:STRING,zip:STRING>'
           ) AS parsed
    FROM orders_json
);

-- ============================================================
-- 3. from_json + explode 展开数组
-- ============================================================
SELECT id, parsed.customer, item.product, item.qty, item.price
FROM (
    SELECT id,
           from_json(data,
               'customer STRING, total DOUBLE, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>'
           ) AS parsed
    FROM orders_json
)
LATERAL VIEW explode(parsed.items) exploded AS item;

-- ============================================================
-- 4. inline 展开结构体数组（Spark 2.0+）
-- ============================================================
SELECT id, customer, product, qty, price
FROM (
    SELECT id,
           from_json(data, 'customer STRING, items ARRAY<STRUCT<product:STRING,qty:INT,price:DOUBLE>>') AS parsed
    FROM orders_json
)
LATERAL VIEW inline(parsed.items) exploded AS product, qty, price
LATERAL VIEW (SELECT parsed.customer) AS t(customer);

-- ============================================================
-- 5. json_tuple（Hive 兼容语法）
-- ============================================================
SELECT o.id, j.customer, j.total
FROM   orders_json o
LATERAL VIEW json_tuple(o.data, 'customer', 'total') j AS customer, total;
