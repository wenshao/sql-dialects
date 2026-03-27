-- TDSQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TDSQL 兼容 MySQL 语法
--       https://cloud.tencent.com/document/product/557

-- ============================================================
-- 与 MySQL 语法相同
-- ============================================================
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- JSON_EXTRACT 提取字段
SELECT id,
       data->>'$.customer'         AS customer,
       JSON_EXTRACT(data, '$.total') AS total
FROM   orders_json;

-- JSON_TABLE 展开数组
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
