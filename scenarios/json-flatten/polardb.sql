-- PolarDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] PolarDB 兼容 MySQL / PostgreSQL 语法
--       https://help.aliyun.com/product/172538.html

-- ============================================================
-- 示例数据（MySQL 兼容模式）
-- ============================================================
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
);

-- ============================================================
-- 1. JSON_EXTRACT 提取字段
-- ============================================================
SELECT id,
       data->>'$.customer'         AS customer,
       JSON_EXTRACT(data, '$.total') AS total,
       data->>'$.address.city'     AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE 展开数组
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;
