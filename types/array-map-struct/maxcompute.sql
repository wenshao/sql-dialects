-- MaxCompute (ODPS): 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] MaxCompute 文档 - ARRAY 类型
--       https://help.aliyun.com/document_detail/159541.html
--   [2] MaxCompute 文档 - MAP 类型
--       https://help.aliyun.com/document_detail/159542.html
--   [3] MaxCompute 文档 - STRUCT 类型
--       https://help.aliyun.com/document_detail/159543.html
--   [4] MaxCompute 文档 - 复杂类型函数
--       https://help.aliyun.com/document_detail/48974.html

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
);

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95)),
    (2, 'Bob',   ARRAY('user', 'tester'), ARRAY(70, 80, 75));

-- 数组索引（从 0 开始）
SELECT tags[0] FROM users;

-- ARRAY 函数
SELECT SIZE(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT SORT_ARRAY(scores) FROM users;
SELECT ARRAY_DISTINCT(tags) FROM users;
SELECT ARRAY_UNION(ARRAY('a','b'), ARRAY('b','c'));
SELECT ARRAY_INTERSECT(ARRAY(1,2,3), ARRAY(2,3,4));
SELECT ARRAY_EXCEPT(ARRAY(1,2,3), ARRAY(2));
SELECT ARRAY_JOIN(tags, ', ') FROM users;
SELECT ARRAY_POSITION(tags, 'admin') FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT CONCAT_WS(',', tags) FROM users;       -- 数组转字符串

-- EXPLODE / LATERAL VIEW
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- POSEXPLODE
SELECT u.name, t.pos, t.tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- COLLECT_LIST / COLLECT_SET
SELECT COLLECT_LIST(name) FROM users;
SELECT COLLECT_SET(name) FROM users;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
);

INSERT INTO products VALUES
    (1, 'Laptop', MAP('brand', 'Dell', 'ram', '16GB'), MAP('price', 999.99));

SELECT attributes['brand'] FROM products;
SELECT MAP_KEYS(attributes) FROM products;
SELECT MAP_VALUES(attributes) FROM products;
SELECT SIZE(attributes) FROM products;

-- Map 展开
SELECT p.name, t.key, t.value
FROM products p
LATERAL VIEW EXPLODE(p.attributes) t AS key, value;

-- STR_TO_MAP
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<city: STRING, zip: STRING>
);

INSERT INTO orders VALUES (
    1,
    NAMED_STRUCT('name', 'Alice', 'email', 'alice@example.com'),
    NAMED_STRUCT('city', 'NYC', 'zip', '10001')
);

SELECT customer.name, address.city FROM orders;

-- ============================================================
-- 嵌套类型
-- ============================================================

CREATE TABLE events (
    id    BIGINT,
    items ARRAY<STRUCT<name: STRING, qty: INT, price: DOUBLE>>
);

SELECT e.id, t.item.name, t.item.qty
FROM events e
LATERAL VIEW EXPLODE(e.items) t AS item;

-- MAP<STRING, ARRAY<STRING>>
-- STRUCT 嵌套 STRUCT

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. MaxCompute 原生支持 ARRAY、MAP、STRUCT
-- 2. 数组下标从 0 开始
-- 3. LATERAL VIEW EXPLODE 展开数组和 Map
-- 4. 与 Hive 语法高度兼容
-- 5. 支持任意深度的嵌套
