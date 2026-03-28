-- Apache Doris: JSON 展平
--
-- 参考资料:
--   [1] Doris - JSON Functions / explode_json_array
--       https://doris.apache.org/docs/sql-manual/sql-functions/json-functions/

-- ============================================================
-- 1. json_extract 提取字段
-- ============================================================
SELECT id,
    json_extract(data, '$.customer') AS customer,
    json_extract(data, '$.total') AS total,
    json_extract(data, '$.address.city') AS city
FROM orders_json;

-- 箭头运算符 (2.1+)
SELECT data->'name', data->>'name' FROM orders_json;

-- ============================================================
-- 2. LATERAL VIEW explode 展开数组
-- ============================================================
SELECT o.id, item
FROM orders_json o
LATERAL VIEW explode_json_array_json(json_extract(o.data, '$.items')) tmp AS item;

-- ============================================================
-- 3. get_json_string / get_json_int
-- ============================================================
SELECT id, get_json_string(data, '$.customer') AS customer,
    get_json_int(data, '$.items[0].qty') AS first_qty
FROM orders_json;

-- 对比:
--   StarRocks:  json_each(3.1+) + UNNEST 展开
--   ClickHouse: JSONExtract* 函数族
--   BigQuery:   JSON_EXTRACT + UNNEST
--   MySQL 8.0:  JSON_TABLE(最强大的 JSON 展平)
