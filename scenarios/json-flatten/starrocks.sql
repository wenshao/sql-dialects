-- StarRocks: JSON 展平
--
-- 参考资料:
--   [1] StarRocks - JSON Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- ============================================================
-- 1. json_query / json_value
-- ============================================================
SELECT id,
    json_query(data, '$.customer') AS customer,
    json_query(data, '$.address.city') AS city
FROM orders_json;

-- 箭头运算符
SELECT data->'name', data->>'name' FROM orders_json;

-- ============================================================
-- 2. UNNEST 展开 JSON 数组 (3.1+)
-- ============================================================
-- SELECT o.id, item FROM orders_json o,
-- UNNEST(CAST(json_query(o.data, '$.items') AS ARRAY<JSON>)) AS t(item);

-- json_each (3.1+): 展开 JSON 对象为键值对
-- SELECT key, value FROM TABLE(json_each('{"a":1,"b":2}'));

-- 对比 Doris: LATERAL VIEW explode_json_array(Hive 风格)
-- StarRocks:   UNNEST + json_each(SQL 标准风格)
