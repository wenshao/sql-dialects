-- MaxCompute (ODPS): JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - JSON Functions
--       https://help.aliyun.com/document_detail/438714.html
--   [2] MaxCompute SQL Reference - LATERAL VIEW
--       https://help.aliyun.com/document_detail/73778.html

-- ============================================================
-- 1. get_json_object 提取字段
-- ============================================================
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.total')         AS total,
       get_json_object(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. LATERAL VIEW explode + JSON
-- ============================================================
-- MaxCompute 2.0 支持复杂类型
-- 将 JSON 数组先用 get_json_object 提取，再用 explode
SELECT o.id,
       get_json_object(o.data, '$.customer') AS customer,
       get_json_object(item, '$.product')    AS product,
       get_json_object(item, '$.qty')        AS qty
FROM   orders_json o
LATERAL VIEW explode(
    split(
        regexp_replace(regexp_replace(
            get_json_object(o.data, '$.items'),
        '^\\[', ''), '\\]$', ''),
        '\\},\\s*\\{'
    )
) t AS item;

-- ============================================================
-- 3. JSON_TUPLE（多字段提取）
-- ============================================================
SELECT o.id, j.customer, j.total
FROM   orders_json o
LATERAL VIEW json_tuple(o.data, 'customer', 'total') j AS customer, total;
