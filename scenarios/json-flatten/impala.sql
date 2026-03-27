-- Impala: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Impala Documentation - Complex Types
--       https://impala.apache.org/docs/build/html/topics/impala_complex_types.html
--   [2] Impala Documentation - get_json_object
--       https://impala.apache.org/docs/build/html/topics/impala_misc_functions.html

-- ============================================================
-- 1. get_json_object 提取字段
-- ============================================================
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.total')         AS total,
       get_json_object(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. 复杂类型（Parquet/ORC 中嵌套结构）
-- ============================================================
-- CREATE TABLE orders_complex (
--     customer STRING,
--     items    ARRAY<STRUCT<product:STRING, qty:INT, price:DOUBLE>>
-- ) STORED AS PARQUET;
-- SELECT o.customer, item.product, item.qty
-- FROM orders_complex o, o.items item;

-- ============================================================
-- 注意: Impala 对 JSON 字符串的直接处理有限
-- 推荐将 JSON 数据以 Parquet/ORC 复杂类型存储
-- ============================================================
