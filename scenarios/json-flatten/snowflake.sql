-- Snowflake: JSON 展平为关系行
--
-- 参考资料:
--   [1] Snowflake SQL Reference - FLATTEN
--       https://docs.snowflake.com/en/sql-reference/functions/flatten

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY TABLE orders_json (id NUMBER AUTOINCREMENT, data VARIANT NOT NULL);
INSERT INTO orders_json (data) SELECT PARSE_JSON('{
  "customer": "Alice", "total": 150.00,
  "items": [{"product": "Widget", "qty": 2, "price": 25.00},
             {"product": "Gadget", "qty": 1, "price": 100.00}],
  "address": {"city": "Beijing", "zip": "100000"}}');
INSERT INTO orders_json (data) SELECT PARSE_JSON('{
  "customer": "Bob", "total": 80.00,
  "items": [{"product": "Widget", "qty": 3, "price": 25.00},
             {"product": "Doohickey", "qty": 1, "price": 5.00}],
  "address": {"city": "Shanghai", "zip": "200000"}}');

-- ============================================================
-- 1. 冒号语法提取 JSON 字段
-- ============================================================

SELECT id,
       data:customer::VARCHAR       AS customer,
       data:total::NUMBER(10,2)     AS total,
       data:address.city::VARCHAR   AS city,
       data:address.zip::VARCHAR    AS zip
FROM orders_json;

-- : 路径运算符是 Snowflake 独有语法:
--   data:field         → 第一层访问（冒号）
--   data:obj.field     → 嵌套访问（点号）
--   data:arr[0]        → 数组索引（方括号）
--   data['field']      → 动态键名（方括号）
-- 对比: PostgreSQL 用 ->/->>，MySQL 用 $.path

-- ============================================================
-- 2. FLATTEN 展开数组（核心用法）
-- ============================================================

SELECT o.id, o.data:customer::VARCHAR AS customer,
       f.VALUE:product::VARCHAR AS product,
       f.VALUE:qty::INT AS qty,
       f.VALUE:price::NUMBER(10,2) AS price,
       f.INDEX AS item_index
FROM orders_json o, LATERAL FLATTEN(INPUT => o.data:items) f;

-- FLATTEN 输出列:
--   SEQ:   序列号（源行标识）
--   KEY:   键名（对象）或 NULL（数组）
--   PATH:  JSON 路径
--   INDEX: 数组索引
--   VALUE: 值（VARIANT）
--   THIS:  被展开的元素

-- ============================================================
-- 3. FLATTEN 展开对象
-- ============================================================

SELECT o.id, f.KEY AS field_name, f.VALUE AS field_value
FROM orders_json o, LATERAL FLATTEN(INPUT => o.data:address) f;

-- ============================================================
-- 4. 递归 FLATTEN
-- ============================================================

SELECT o.id, f.KEY, f.PATH, f.VALUE
FROM orders_json o, LATERAL FLATTEN(INPUT => o.data, RECURSIVE => TRUE) f
WHERE TYPEOF(f.VALUE) NOT IN ('OBJECT', 'ARRAY');
-- RECURSIVE => TRUE: 递归展开所有嵌套层级
-- 只保留叶节点（排除 OBJECT 和 ARRAY 类型的中间节点）

-- ============================================================
-- 5. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- FLATTEN 是 Snowflake 将半结构化数据关系化的核心机制。
-- 对比其他引擎的等价操作:
--   PostgreSQL: jsonb_array_elements / jsonb_each
--   MySQL:      JSON_TABLE（8.0.4+，语法更复杂）
--   BigQuery:   UNNEST(JSON_EXTRACT_ARRAY(...))
--   Oracle:     JSON_TABLE（最接近 SQL 标准）
--
-- Snowflake FLATTEN 的优势:
--   (a) 统一接口: 数组和对象都用 FLATTEN，只是输出列不同
--   (b) 递归支持: RECURSIVE => TRUE 自动展开所有嵌套
--   (c) OUTER 模式: OUTER => TRUE 保留空数组的行（类似 LEFT JOIN）
--
-- 对引擎开发者的启示:
--   LATERAL + 表函数是展开嵌套数据的标准范式。
--   关键实现: 表函数的每次调用产生多行输出 → 与外部表做交叉连接。

-- ============================================================
-- 6. GET_PATH / GET 动态路径
-- ============================================================

SELECT id,
       GET_PATH(data, 'customer') AS customer,
       GET_PATH(data, 'items[0].product') AS first_product
FROM orders_json;
-- GET_PATH 接受字符串路径 → 适合动态路径（路径名运行时确定）
-- data:path 是编译时静态路径

-- ============================================================
-- 横向对比: JSON 展开能力
-- ============================================================
-- 能力          | Snowflake        | BigQuery        | PostgreSQL     | MySQL
-- 路径访问      | : 冒号语法       | JSON_VALUE      | -> / ->>       | $.path
-- 数组展开      | FLATTEN          | UNNEST          | jsonb_array_el | JSON_TABLE
-- 对象展开      | FLATTEN          | 不支持          | jsonb_each     | JSON_TABLE
-- 递归展开      | RECURSIVE=>TRUE  | 不支持          | 不支持         | 不支持
-- 空数组处理    | OUTER=>TRUE      | LEFT JOIN       | LEFT JOIN      | 不支持
-- 动态路径      | GET_PATH         | JSON_QUERY      | jsonb_path_*   | JSON_EXTRACT
