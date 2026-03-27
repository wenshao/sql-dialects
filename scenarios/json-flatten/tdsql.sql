-- TDSQL: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TDSQL 兼容 MySQL 语法
--       https://cloud.tencent.com/document/product/557
--   [2] MySQL 8.0 Reference Manual - JSON Functions
--       https://dev.mysql.com/doc/refman/8.0/en/json-functions.html
--   [3] MySQL 8.0 Reference Manual - JSON_TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/json-table-functions.html

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO orders_json (data) VALUES
    ('{"customer": "Alice", "total": 150.00, "items": [
        {"product": "Widget", "qty": 2, "price": 25.00},
        {"product": "Gadget", "qty": 1, "price": 100.00}
      ],
      "address": {"city": "Beijing", "zip": "100000"}
    }'),
    ('{"customer": "Bob", "total": 80.00, "items": [
        {"product": "Widget", "qty": 3, "price": 25.00},
        {"product": "Doohickey", "qty": 1, "price": 5.00}
      ],
      "address": {"city": "Shanghai", "zip": "200000"}
    }');

-- ============================================================
-- 2. 提取 JSON 字段为列
-- ============================================================

SELECT id,
       data->>'$.customer'                       AS customer,
       data->>'$.total'                          AS total,
       CAST(data->>'$.total' AS DECIMAL(10,2))   AS total_num,
       data->>'$.address.city'                   AS city,
       data->>'$.address.zip'                    AS zip
FROM   orders_json;

-- TDSQL 兼容 MySQL 的 JSON 运算符:
--   ->> : 提取值并去引号（返回文本）
--   ->  : 提取值保留引号（返回 JSON 字符串）
--   MySQL 路径语法: $.key, $.a.b, $.items[0]

-- ============================================================
-- 3. JSON_TABLE 展开数组为多行（推荐）
-- ============================================================

SELECT o.id,
       o.data->>'$.customer' AS customer,
       j.rownum,
       j.product,
       j.qty,
       j.price
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

-- 设计分析: JSON_TABLE 是 MySQL 8.0.4+ 的声明式展平方案
--   一步定义列名、类型和路径映射
--   FOR ORDINALITY 提供行序号
--   比 LATERAL + 逐字段提取更简洁
--   TDSQL 作为 MySQL 兼容引擎完全支持此语法

-- ============================================================
-- 4. 嵌套 JSON_TABLE（同时展开多层结构）
-- ============================================================

SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               total    DECIMAL(10,2) PATH '$.total',
               city     VARCHAR(100)  PATH '$.address.city',
               NESTED PATH '$.items[*]' COLUMNS (
                   rownum  FOR ORDINALITY,
                   product VARCHAR(100) PATH '$.product',
                   qty     INT          PATH '$.qty',
                   price   DECIMAL(10,2) PATH '$.price'
               )
           )
       ) AS j;

-- NESTED PATH 支持多层嵌套展平
-- 外层提取 customer、total、city
-- 内层展开 items 数组

-- ============================================================
-- 5. JSON_EXTRACT 和 JSON_UNQUOTE（低版本兼容）
-- ============================================================

SELECT id,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.customer')) AS customer,
       JSON_EXTRACT(data, '$.total')                   AS total_raw,
       CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.total')) AS DECIMAL(10,2)) AS total
FROM   orders_json;

-- ->> 运算符是 JSON_UNQUOTE(JSON_EXTRACT(...)) 的简写
-- 在 MySQL 5.7.13+ / TDSQL 中可用

-- ============================================================
-- 6. JSON_KEYS 查看对象键
-- ============================================================

SELECT id, JSON_KEYS(data) AS top_keys
FROM   orders_json;

-- JSON_KEYS 返回 JSON 对象的所有键名（JSON 数组形式）

-- ============================================================
-- 7. 条件过滤 JSON 字段
-- ============================================================

SELECT id, data->>'$.customer' AS customer
FROM   orders_json
WHERE  CAST(data->>'$.total' AS DECIMAL(10,2)) > 100
  AND  data->>'$.address.city' = 'Beijing';

-- JSON 提取的字段可以直接用于 WHERE 条件
-- 建议对高频查询路径创建虚拟列和索引:
-- ALTER TABLE orders_json
--     ADD COLUMN customer_name VARCHAR(100)
--         GENERATED ALWAYS AS (data->>'$.customer') STORED,
--     ADD INDEX idx_customer (customer_name);

-- ============================================================
-- 8. JSON 聚合（反向: 行转 JSON）
-- ============================================================

SELECT data->>'$.customer' AS customer,
       JSON_ARRAYAGG(
           JSON_OBJECT('product', j.product, 'qty', j.qty)
       ) AS items_summary
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty'
           )
       ) AS j
GROUP  BY o.id, o.data->>'$.customer';

-- ============================================================
-- 9. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. TDSQL JSON 能力:
--   完全兼容 MySQL 8.0 的 JSON 函数和运算符
--   JSON_TABLE 提供声明式的数组展平
--   支持虚拟列和函数索引优化 JSON 查询
--
-- 2. 与其他 MySQL 兼容引擎对比:
--   TDSQL:      兼容 MySQL 8.0 JSON 功能，分布式架构
--   TiDB:       兼容 MySQL 8.0 JSON 功能
--   MariaDB:    部分兼容（JSON_TABLE 支持有限）
--   PolarDB:    兼容 MySQL 8.0 JSON 功能
--
-- 对引擎开发者:
--   JSON_TABLE 是最用户友好的 JSON 展平方案
--   MySQL 生态的 JSON 函数已经非常成熟
--   虚拟列 + 索引是 JSON 查询性能优化的关键
--   分布式场景下需关注 JSON 函数的下推能力
