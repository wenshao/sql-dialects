-- 人大金仓 (KingbaseES): JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] KingbaseES 兼容 PostgreSQL JSON 函数
--       https://help.kingbase.com.cn/

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

-- jsonb_to_recordset
SELECT o.id, r.*
FROM   orders_json o,
       LATERAL jsonb_to_recordset(o.data->'items')
              AS r(product TEXT, qty INT, price NUMERIC);
