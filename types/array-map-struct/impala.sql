-- Apache Impala: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Apache Impala Documentation - Complex Types
--       https://impala.apache.org/docs/build/html/topics/impala_complex_types.html
--   [2] Apache Impala Documentation - ARRAY Type
--       https://impala.apache.org/docs/build/html/topics/impala_array.html
--   [3] Apache Impala Documentation - MAP Type
--       https://impala.apache.org/docs/build/html/topics/impala_map.html
--   [4] Apache Impala Documentation - STRUCT Type
--       https://impala.apache.org/docs/build/html/topics/impala_struct.html

-- ============================================================
-- ARRAY 类型（Impala 2.3+, Parquet/ORC 格式）
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
)
STORED AS PARQUET;

-- 查询数组（使用子查询语法）
SELECT u.name, t.item AS tag
FROM users u, u.tags t;

-- 数组索引
SELECT tags.item FROM users.tags;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>
)
STORED AS PARQUET;

SELECT p.name, a.key, a.value
FROM products p, p.attributes a;

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<city: STRING, zip: STRING>
)
STORED AS PARQUET;

SELECT customer.name, address.city FROM orders;

-- ============================================================
-- 嵌套类型
-- ============================================================

CREATE TABLE events (
    id    BIGINT,
    items ARRAY<STRUCT<name: STRING, qty: INT, price: DOUBLE>>
)
STORED AS PARQUET;

SELECT e.id, i.item.name, i.item.qty
FROM events e, e.items i;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 复杂类型只支持 Parquet 和 ORC 格式
-- 2. 使用子查询语法访问嵌套数据（非 UNNEST/EXPLODE）
-- 3. 不支持在 INSERT 中直接构造复杂类型值
-- 4. 需要从外部文件加载复杂类型数据
-- 5. 不支持 ARRAY_AGG / COLLECT_LIST
