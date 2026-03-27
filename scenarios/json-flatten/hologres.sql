-- Hologres: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Hologres 兼容 PostgreSQL JSON 函数
--       https://help.aliyun.com/document_detail/416498.html

-- ============================================================
-- 与 PostgreSQL 语法相同
-- ============================================================
CREATE TABLE orders_json (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

-- 提取字段
SELECT id, data->>'customer' AS customer, data->'address'->>'city' AS city
FROM   orders_json;

-- 展开数组
SELECT o.id, item->>'product' AS product, (item->>'qty')::INT AS qty
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;
