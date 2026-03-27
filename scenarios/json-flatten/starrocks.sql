-- StarRocks: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] StarRocks Documentation - JSON Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/json-functions/
--   [2] StarRocks Documentation - unnest
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/array-functions/unnest/

-- ============================================================
-- 示例数据（StarRocks 2.5+ 支持 JSON 类型）
-- ============================================================
CREATE TABLE orders_json (
    id   INT,
    data JSON
) DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- ============================================================
-- 1. json_query / json_value 提取字段
-- ============================================================
SELECT id,
       get_json_string(CAST(data AS VARCHAR), '$.customer')  AS customer,
       get_json_double(CAST(data AS VARCHAR), '$.total')     AS total
FROM   orders_json;

-- ============================================================
-- 2. json_each 展开对象
-- ============================================================
-- StarRocks 3.1+ 支持 JSON 数组展开
-- SELECT o.id, j.*
-- FROM orders_json o, LATERAL json_each(o.data->'items') j;

-- ============================================================
-- 3. get_json_string 逐个提取
-- ============================================================
SELECT id,
       get_json_string(CAST(data AS VARCHAR), '$.items[0].product') AS first_product,
       get_json_string(CAST(data AS VARCHAR), '$.items[1].product') AS second_product
FROM   orders_json;
