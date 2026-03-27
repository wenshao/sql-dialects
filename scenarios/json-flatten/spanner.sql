-- Cloud Spanner: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Cloud Spanner - JSON Data Type
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types#json_type
--   [2] Cloud Spanner - JSON Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/json_functions
--   [3] Cloud Spanner - Query Syntax (UNNEST)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE orders_json (
    id   INT64 NOT NULL,
    data JSON
) PRIMARY KEY (id);

-- DML 插入数据（DDL 和 DML 需分开执行）
-- INSERT INTO orders_json (id, data) VALUES
--     (1, JSON '{"customer": "Alice", "total": 150.0, "items": [{"product": "Widget", "qty": 2, "price": 25.0}, {"product": "Gadget", "qty": 1, "price": 100.0}], "address": {"city": "Beijing", "zip": "100000"}}'),
--     (2, JSON '{"customer": "Bob", "total": 80.0, "items": [{"product": "Widget", "qty": 3, "price": 25.0}, {"product": "Doohickey", "qty": 1, "price": 5.0}], "address": {"city": "Shanghai", "zip": "200000"}}');

-- 注意: Spanner 使用 JSON '...' 构造 JSON 字面量

-- ============================================================
-- 2. JSON_VALUE 提取标量字段
-- ============================================================

SELECT id,
       JSON_VALUE(data, '$.customer')                  AS customer,
       CAST(JSON_VALUE(data, '$.total') AS FLOAT64)    AS total,
       JSON_VALUE(data, '$.address.city')              AS city,
       JSON_VALUE(data, '$.address.zip')               AS zip
FROM   orders_json;

-- JSON_VALUE: 提取 JSON 标量值，返回 STRING 类型
--   支持标准 JSONPath 语法（$.key, $.a.b, $.items[0]）
--   需要 CAST 转换为数值类型
--   如果值不是标量（如对象或数组），返回 NULL

-- ============================================================
-- 3. JSON_QUERY 提取 JSON 片段
-- ============================================================

SELECT id,
       JSON_QUERY(data, '$.items')    AS items_array,
       JSON_QUERY(data, '$.address')  AS address_obj
FROM   orders_json;

-- JSON_QUERY vs JSON_VALUE:
--   JSON_VALUE: 返回标量值（去引号的字符串）
--   JSON_QUERY: 返回 JSON 片段（保留 JSON 格式）
--   类似于 Oracle 的 JSON_VALUE vs JSON_QUERY

-- ============================================================
-- 4. JSON_QUERY_ARRAY + UNNEST 展开数组
-- ============================================================

SELECT o.id,
       JSON_VALUE(item, '$.product')              AS product,
       CAST(JSON_VALUE(item, '$.qty') AS INT64)   AS qty,
       CAST(JSON_VALUE(item, '$.price') AS FLOAT64) AS price
FROM   orders_json o,
       UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item;

-- 设计分析: 三步组合
--   JSON_QUERY_ARRAY: 提取 JSON 数组为 Spanner ARRAY<JSON>
--   UNNEST: 将 ARRAY 展开为多行
--   JSON_VALUE: 从每行 JSON 中提取字段值
--   这与 BigQuery 的模式非常相似

-- ============================================================
-- 5. 带序号的数组展开
-- ============================================================

SELECT o.id,
       pos,
       JSON_VALUE(item, '$.product') AS product
FROM   orders_json o,
       UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS item WITH OFFSET AS pos
ORDER  BY o.id, pos;

-- WITH OFFSET 为数组元素添加序号（从 0 开始）
-- 可以用于保留原始顺序

-- ============================================================
-- 6. LATERAL 关联展开
-- ============================================================

SELECT o.id, o.data, item.*
FROM   orders_json o,
       LATERAL (
         SELECT JSON_VALUE(elem, '$.product')              AS product,
                CAST(JSON_VALUE(elem, '$.qty') AS INT64)   AS qty,
                CAST(JSON_VALUE(elem, '$.price') AS FLOAT64) AS price
         FROM   UNNEST(JSON_QUERY_ARRAY(o.data, '$.items')) AS elem
       ) item;

-- LATERAL 允许子查询引用外表的列

-- ============================================================
-- 7. JSON 数组聚合（反向: 行转 JSON 数组）
-- ============================================================

-- SELECT customer,
--        TO_JSON_ARRAY(ARRAY_AGG(
--          STRUCT<product STRING, qty INT64, price FLOAT64>(product, qty, price)
--        )) AS items_json
-- FROM expanded_data
-- GROUP BY customer;

-- ============================================================
-- 8. JSON 类型查询过滤
-- ============================================================

SELECT id, JSON_VALUE(data, '$.customer') AS customer
FROM   orders_json
WHERE  JSON_VALUE(data, '$.address.city') = 'Beijing';

-- Spanner 支持 JSON 字段在 WHERE 条件中使用
-- 注意: 过滤可能无法利用索引（取决于查询计划）

-- ============================================================
-- 9. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. Spanner JSON 能力:
--   JSON 类型: 原生支持（GoogleSQL）
--   JSON_VALUE / JSON_QUERY: SQL/JSON 标准函数
--   JSON_QUERY_ARRAY + UNNEST: 数组展开模式
--   JSONPath 支持: 标准 JSONPath 语法
--
-- 2. 与其他云数据库对比:
--   BigQuery:   JSON 类似，SPLIT 替换为 JSON_QUERY_ARRAY
--   PostgreSQL: JSONB + jsonb_array_elements（更成熟）
--   MySQL:      JSON_TABLE（声明式展平）
--   DynamoDB:   文档模型原生支持
--
-- 对引擎开发者:
--   JSON_QUERY_ARRAY + UNNEST 是 GoogleSQL 的标准展开模式
--   分离"提取"和"展开"操作提供更好的组合性
--   JSON_VALUE / JSON_QUERY 的双函数设计遵循 SQL/JSON 标准
--   WITH OFFSET 是保留顺序的优秀设计细节
