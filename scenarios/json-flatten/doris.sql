-- Doris: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Apache Doris Documentation - JSON Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/json-functions/
--   [2] Apache Doris Documentation - explode_json_array
--       https://doris.apache.org/docs/sql-manual/sql-functions/table-functions/explode-json-array

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT,
    data VARCHAR(10000)
) DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- ============================================================
-- 1. json_extract / jsonb_extract 提取字段（Doris 1.2+）
-- ============================================================
SELECT id,
       json_extract(data, '$.customer')      AS customer,
       json_extract(data, '$.total')         AS total,
       json_extract(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. LATERAL VIEW explode_json_array 展开数组
-- ============================================================
SELECT o.id, item
FROM   orders_json o
LATERAL VIEW explode_json_array_json(
    json_extract(o.data, '$.items')
) tmp AS item;

-- ============================================================
-- 3. get_json_string / get_json_int
-- ============================================================
SELECT id,
       get_json_string(data, '$.customer')     AS customer,
       get_json_int(data, '$.items[0].qty')    AS first_qty
FROM   orders_json;
