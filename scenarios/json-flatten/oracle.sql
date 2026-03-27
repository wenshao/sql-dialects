-- Oracle: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - JSON_TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/JSON_TABLE.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders_json (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data CLOB CONSTRAINT chk_json CHECK (data IS JSON)
);

INSERT INTO orders_json (data) VALUES
('{"customer": "Alice", "total": 150.00, "items": [
    {"product": "Widget", "qty": 2, "price": 25.00},
    {"product": "Gadget", "qty": 1, "price": 100.00}
  ], "address": {"city": "Beijing", "zip": "100000"}}');
INSERT INTO orders_json (data) VALUES
('{"customer": "Bob", "total": 80.00, "items": [
    {"product": "Widget", "qty": 3, "price": 25.00},
    {"product": "Doohickey", "qty": 1, "price": 5.00}
  ], "address": {"city": "Shanghai", "zip": "200000"}}');
COMMIT;

-- ============================================================
-- 1. JSON_VALUE: 提取标量字段
-- ============================================================

SELECT id,
       JSON_VALUE(data, '$.customer') AS customer,
       JSON_VALUE(data, '$.total' RETURNING NUMBER) AS total,
       JSON_VALUE(data, '$.address.city') AS city
FROM orders_json;

-- ============================================================
-- 2. JSON_TABLE: 展开数组为多行（12c+，Oracle 最早且最完整的实现）
-- ============================================================

SELECT o.id, j.*
FROM orders_json o,
     JSON_TABLE(o.data, '$.items[*]' COLUMNS (
         rownum  FOR ORDINALITY,
         product VARCHAR2(100) PATH '$.product',
         qty     NUMBER        PATH '$.qty',
         price   NUMBER(10,2)  PATH '$.price'
     )) j;

-- FOR ORDINALITY: 自动生成行号（Oracle 独有特性）

-- ============================================================
-- 3. 嵌套 JSON_TABLE: 完全展平
-- ============================================================

SELECT o.id, j.*
FROM orders_json o,
     JSON_TABLE(o.data, '$' COLUMNS (
         customer VARCHAR2(100) PATH '$.customer',
         city     VARCHAR2(100) PATH '$.address.city',
         NESTED PATH '$.items[*]' COLUMNS (
             product VARCHAR2(100) PATH '$.product',
             qty     NUMBER        PATH '$.qty',
             price   NUMBER(10,2)  PATH '$.price'
         )
     )) j;

-- 设计分析:
--   JSON_TABLE 是 SQL:2016 标准的核心特性，Oracle 12c 是最早实现的数据库。
--   NESTED PATH 允许在一个 JSON_TABLE 调用中同时展开多层嵌套。
--   这比 PostgreSQL 的 jsonb_array_elements + LATERAL 方式更统一。

-- ============================================================
-- 4. JSON_QUERY / JSON_EXISTS
-- ============================================================

-- 提取子 JSON 片段
SELECT id, JSON_QUERY(data, '$.items') AS items_array
FROM orders_json;

-- 条件过滤（SQL/JSON Path 语法）
SELECT id, JSON_VALUE(data, '$.customer') AS customer
FROM orders_json
WHERE JSON_EXISTS(data, '$.items[*]?(@.price > 50)');

-- ============================================================
-- 5. 点表示法（12c+，简化 JSON 访问）
-- ============================================================

SELECT o.id, o.data.customer, o.data.address.city
FROM orders_json o;

-- 点表示法需要 IS JSON 约束（或 JSON 类型），
-- 这是 Oracle 最简洁的 JSON 访问方式。

-- ============================================================
-- 6. '' = NULL 对 JSON 的影响
-- ============================================================

-- JSON 中 "" (空字符串) 被 JSON_VALUE 返回为 NULL
-- 因为 JSON_VALUE 返回 VARCHAR2，而 '' = NULL
-- 这导致无法区分 JSON 中的 null 和 ""

-- ============================================================
-- 7. 对引擎开发者的总结
-- ============================================================
-- 1. JSON_TABLE 是 JSON-关系桥梁的标准方案，Oracle 12c 最早实现。
-- 2. NESTED PATH 在一次调用中展开多层嵌套，比多次 LATERAL 更统一。
-- 3. 点表示法（o.data.field）是最佳用户体验的 JSON 访问方式。
-- 4. '' = NULL 导致 JSON 空字符串值被误读为 NULL。
-- 5. FOR ORDINALITY 自动生成行号，对数组元素定位很有用。
