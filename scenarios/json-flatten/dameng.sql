-- 达梦 (Dameng): JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] 达梦数据库 SQL 参考手册 - JSON 函数
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/
--   [2] 达梦兼容 Oracle JSON 语法

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    data CLOB
);

-- ============================================================
-- 1. JSON_VALUE 提取字段（兼容 Oracle）
-- ============================================================
SELECT id,
       JSON_VALUE(data, '$.customer')      AS customer,
       JSON_VALUE(data, '$.total')         AS total,
       JSON_VALUE(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. JSON_TABLE 展开数组
-- ============================================================
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) j;
