-- PostgreSQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - JSON Functions
--       https://www.postgresql.org/docs/current/functions-json.html

-- ============================================================
-- 1. 提取 JSON 字段为列
-- ============================================================

SELECT id,
       data->>'customer' AS customer,
       (data->>'total')::NUMERIC AS total,
       data->'address'->>'city' AS city
FROM orders_json;

-- ============================================================
-- 2. 展开 JSON 数组 (jsonb_array_elements, 9.4+)
-- ============================================================

SELECT o.id, o.data->>'customer' AS customer,
       item->>'product' AS product,
       (item->>'qty')::INT AS qty,
       (item->>'price')::NUMERIC AS price
FROM orders_json o,
     LATERAL jsonb_array_elements(o.data->'items') AS item;

-- 设计分析: LATERAL + jsonb_array_elements
--   jsonb_array_elements 是 SRF（Set-Returning Function），返回多行。
--   LATERAL 让它可以引用外表的列（o.data->'items'）。
--   结合 ->> 运算符提取文本值，:: 运算符转换类型。
--   这三个 PostgreSQL 特性组合成了强大的 JSON 展平能力。

-- ============================================================
-- 3. 展开 JSON 对象键值对 (jsonb_each)
-- ============================================================

SELECT o.id, kv.key, kv.value
FROM orders_json o, LATERAL jsonb_each(o.data->'address') AS kv;

-- ============================================================
-- 4. jsonb_to_recordset: 直接转关系记录 (9.4+)
-- ============================================================

SELECT o.id, o.data->>'customer' AS customer, r.*
FROM orders_json o,
     LATERAL jsonb_to_recordset(o.data->'items')
            AS r(product TEXT, qty INT, price NUMERIC);

-- 设计分析: jsonb_to_recordset vs jsonb_array_elements
--   jsonb_to_recordset 直接将 JSON 数组转为关系表（指定列名和类型）
--   比 jsonb_array_elements + 逐字段 ->> 提取更简洁

-- ============================================================
-- 5. JSON Path 查询 (12+, SQL/JSON 标准)
-- ============================================================

SELECT o.id,
       jsonb_path_query_first(o.data, '$.customer') AS customer,
       item.*
FROM orders_json o,
     LATERAL jsonb_path_query(o.data, '$.items[*]') AS raw_item,
     LATERAL jsonb_to_record(raw_item) AS item(product TEXT, qty INT, price NUMERIC);

-- 17+: JSON_TABLE（SQL 标准，一步完成展平）
-- SELECT * FROM orders_json,
--     JSON_TABLE(data, '$.items[*]' COLUMNS (
--         product TEXT PATH '$.product',
--         qty INT PATH '$.qty',
--         price NUMERIC PATH '$.price'
--     ));

-- ============================================================
-- 6. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. JSON 展平语法:
--   PostgreSQL: LATERAL + jsonb_array_elements / jsonb_to_recordset
--   MySQL:      JSON_TABLE (8.0+, 一步完成)
--   Oracle:     JSON_TABLE (12c+)
--   SQL Server: OPENJSON (2016+)
--   BigQuery:   UNNEST(JSON_EXTRACT_ARRAY(...))
--
-- 2. PostgreSQL 的方式更灵活但步骤更多:
--   MySQL/Oracle 的 JSON_TABLE 是"声明式"——一步定义列映射
--   PostgreSQL 的 LATERAL + SRF 是"组合式"——多个函数组合
--   PostgreSQL 17 的 JSON_TABLE 填补了这个空白
--
-- 对引擎开发者:
--   LATERAL + SRF 的"组合式"设计更通用（不仅限于 JSON）。
--   但 JSON_TABLE 的声明式语法对用户更友好。
--   理想方案: 同时支持两种方式。
