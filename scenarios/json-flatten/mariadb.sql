-- MariaDB: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - JSON Functions
--       https://mariadb.com/kb/en/json-functions/
--   [2] MariaDB Knowledge Base - JSON_TABLE
--       https://mariadb.com/kb/en/json_table/
--   [3] MariaDB Knowledge Base - JSON_VALUE
--       https://mariadb.com/kb/en/json_value/

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL              -- MariaDB 10.2+ 支持 JSON（别名 LONGTEXT）
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO orders_json (data) VALUES
('{"customer": "Alice", "total": 150.00, "items": [{"product": "Widget", "qty": 2, "price": 25.00}, {"product": "Gadget", "qty": 1, "price": 100.00}], "address": {"city": "Beijing", "zip": "100000"}}'),
('{"customer": "Bob", "total": 80.00, "items": [{"product": "Widget", "qty": 3, "price": 25.00}, {"product": "Doohickey", "qty": 1, "price": 5.00}], "address": {"city": "Shanghai", "zip": "200000"}}');

-- ============================================================
-- 1. 提取 JSON 字段为列 (JSON_VALUE, MariaDB 10.2+)
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')        AS customer,
       JSON_VALUE(data, '$.total')           AS total,
       JSON_VALUE(data, '$.address.city')    AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE 展开数组（MariaDB 10.6+）
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               rownum  FOR ORDINALITY,
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;

-- ============================================================
-- 3. 嵌套 JSON_TABLE
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               city     VARCHAR(100) PATH '$.address.city',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR(100) PATH '$.product',
                   qty     INT          PATH '$.qty',
                   price   DECIMAL(10,2) PATH '$.price'
               )
           )
       ) AS j;

-- ============================================================
-- 4. JSON_EXTRACT + 序列（MariaDB 10.2+, JSON_TABLE 之前的方法）
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer') AS customer,
       JSON_VALUE(
           JSON_EXTRACT(o.data, CONCAT('$.items[', s.seq - 1, '].product')),
           '$'
       ) AS product
FROM   orders_json o
JOIN   seq_1_to_100 s
  ON   s.seq <= JSON_LENGTH(o.data, '$.items');
