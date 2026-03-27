-- SQL Server: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Microsoft Docs - OPENJSON
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql
--   [2] Microsoft Docs - JSON_VALUE / JSON_QUERY
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/json-value-transact-sql
--   [3] Microsoft Docs - JSON_TABLE (SQL Server 2025 预览)
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/json-table-transact-sql

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    data NVARCHAR(MAX) NOT NULL    -- SQL Server 没有原生 JSON 类型
);

INSERT INTO orders_json (data) VALUES
(N'{"customer": "Alice", "total": 150.00, "items": [
    {"product": "Widget", "qty": 2, "price": 25.00},
    {"product": "Gadget", "qty": 1, "price": 100.00}
  ],
  "address": {"city": "Beijing", "zip": "100000"}
}'),
(N'{"customer": "Bob", "total": 80.00, "items": [
    {"product": "Widget", "qty": 3, "price": 25.00},
    {"product": "Doohickey", "qty": 1, "price": 5.00}
  ],
  "address": {"city": "Shanghai", "zip": "200000"}
}');

-- ============================================================
-- 1. 提取 JSON 字段为列 (JSON_VALUE / JSON_QUERY)
-- 适用版本: SQL Server 2016+
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')        AS customer,
       JSON_VALUE(data, '$.total')           AS total,
       JSON_VALUE(data, '$.address.city')    AS city,
       JSON_VALUE(data, '$.address.zip')     AS zip
FROM   orders_json;

-- ============================================================
-- 2. OPENJSON 展开数组为多行（推荐, SQL Server 2016+）
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer') AS customer,
       j.*
FROM   orders_json o
CROSS APPLY OPENJSON(o.data, '$.items')
       WITH (
           product NVARCHAR(100) '$.product',
           qty     INT           '$.qty',
           price   DECIMAL(10,2) '$.price'
       ) AS j;

-- ============================================================
-- 3. OPENJSON 展开对象键值对
-- ============================================================
SELECT o.id, j.[key], j.[value], j.[type]
FROM   orders_json o
CROSS APPLY OPENJSON(o.data) AS j;

-- ============================================================
-- 4. 嵌套 OPENJSON（多层展平）
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer')      AS customer,
       JSON_VALUE(o.data, '$.address.city')  AS city,
       items.*
FROM   orders_json o
CROSS APPLY OPENJSON(o.data, '$.items')
       WITH (
           product NVARCHAR(100) '$.product',
           qty     INT           '$.qty',
           price   DECIMAL(10,2) '$.price'
       ) AS items;

-- ============================================================
-- 5. ISJSON 验证 JSON 格式
-- ============================================================
SELECT id, ISJSON(data) AS is_valid_json FROM orders_json;

-- ============================================================
-- 6. JSON_MODIFY 更新 JSON 值
-- ============================================================
UPDATE orders_json
SET    data = JSON_MODIFY(data, '$.address.city', N'Shenzhen')
WHERE  id = 1;
