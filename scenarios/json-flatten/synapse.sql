-- Synapse: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Azure Synapse Analytics - OPENJSON
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/query-json-files
--   [2] Azure Synapse Analytics - JSON Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/json-value-transact-sql

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT IDENTITY(1,1),
    data NVARCHAR(MAX)
);

-- ============================================================
-- 1. JSON_VALUE 提取字段
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')      AS customer,
       JSON_VALUE(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. OPENJSON 展开数组（推荐）
-- ============================================================
SELECT o.id, j.*
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
-- 4. Serverless SQL Pool 查询 JSON 文件
-- ============================================================
-- SELECT j.*
-- FROM OPENROWSET(
--     BULK 'https://storage.blob.core.windows.net/data/*.json',
--     FORMAT = 'CSV', FIELDTERMINATOR = '0x0b', FIELDQUOTE = '0x0b'
-- ) WITH (doc NVARCHAR(MAX)) AS r
-- CROSS APPLY OPENJSON(r.doc) WITH (...) AS j;
