-- SQL Server: JSON 展平为关系行
--
-- 参考资料:
--   [1] SQL Server - OPENJSON
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (id INT IDENTITY(1,1) PRIMARY KEY, data NVARCHAR(MAX));
INSERT INTO orders_json (data) VALUES
(N'{"customer":"Alice","total":150,"items":[
    {"product":"Widget","qty":2,"price":25},
    {"product":"Gadget","qty":1,"price":100}
  ],"address":{"city":"Beijing","zip":"100000"}}'),
(N'{"customer":"Bob","total":80,"items":[
    {"product":"Widget","qty":3,"price":25},
    {"product":"Doohickey","qty":1,"price":5}
  ],"address":{"city":"Shanghai","zip":"200000"}}');

-- ============================================================
-- 1. 提取标量字段
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')     AS customer,
       JSON_VALUE(data, '$.total')        AS total,
       JSON_VALUE(data, '$.address.city') AS city
FROM orders_json;

-- ============================================================
-- 2. OPENJSON + CROSS APPLY: 展开数组（核心模式）
-- ============================================================
SELECT o.id, JSON_VALUE(o.data, '$.customer') AS customer, j.*
FROM orders_json o
CROSS APPLY OPENJSON(o.data, '$.items') WITH (
    product NVARCHAR(100) '$.product',
    qty     INT           '$.qty',
    price   DECIMAL(10,2) '$.price'
) AS j;

-- 设计分析（对引擎开发者）:
--   OPENJSON + WITH 子句是 SQL Server 的 JSON_TABLE 等价。
--   SQL:2016 标准定义了 JSON_TABLE，MySQL 8.0/Oracle 12c 使用标准语法。
--   SQL Server 选择了独有的 OPENJSON 语法——功能等价但不兼容标准。
--
--   CROSS APPLY + OPENJSON 的组合是 SQL Server JSON 查询的核心模式:
--   左表的每一行，OPENJSON 展开其 JSON 字段为多行。

-- ============================================================
-- 3. 展开对象为键值对
-- ============================================================
SELECT o.id, j.[key], j.[value], j.[type]
FROM orders_json o CROSS APPLY OPENJSON(o.data) AS j;
-- type: 0=null, 1=string, 2=number, 3=boolean, 4=array, 5=object

-- ============================================================
-- 4. 多层嵌套展平
-- ============================================================
SELECT o.id,
       JSON_VALUE(o.data, '$.customer')     AS customer,
       JSON_VALUE(o.data, '$.address.city') AS city,
       items.product, items.qty, items.price
FROM orders_json o
CROSS APPLY OPENJSON(o.data, '$.items') WITH (
    product NVARCHAR(100) '$.product',
    qty     INT           '$.qty',
    price   DECIMAL(10,2) '$.price'
) AS items;

-- ============================================================
-- 5. ISJSON 验证 + JSON_MODIFY 更新
-- ============================================================
SELECT id, ISJSON(data) AS is_valid FROM orders_json;

UPDATE orders_json
SET data = JSON_MODIFY(data, '$.address.city', N'Shenzhen')
WHERE id = 1;

-- ============================================================
-- 6. 性能优化: 计算列索引
-- ============================================================
ALTER TABLE orders_json ADD customer AS JSON_VALUE(data, '$.customer');
CREATE INDEX ix_customer ON orders_json (customer);

-- 对引擎开发者的启示:
--   SQL Server 的 JSON 没有二进制格式（存储在 NVARCHAR 中），
--   每次 OPENJSON 调用都需要解析 JSON 文本。
--   对于频繁查询的 JSON 路径，计算列 + 索引是必要的优化手段。
--   PostgreSQL 的 jsonb 通过二进制格式 + GIN 索引避免了这个问题。
