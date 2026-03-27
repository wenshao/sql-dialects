-- Apache Doris: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Apache Doris Documentation - ARRAY Type
--       https://doris.apache.org/docs/sql-manual/data-types/ARRAY
--   [2] Apache Doris Documentation - MAP Type
--       https://doris.apache.org/docs/sql-manual/data-types/MAP
--   [3] Apache Doris Documentation - STRUCT Type
--       https://doris.apache.org/docs/sql-manual/data-types/STRUCT
--   [4] Apache Doris Documentation - Array Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/array-functions/

-- ============================================================
-- ARRAY 类型（Doris 1.2+）
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   VARCHAR(100),
    tags   ARRAY<VARCHAR(50)>,
    scores ARRAY<INT>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO users VALUES
    (1, 'Alice', ['admin', 'dev'], [90, 85, 95]),
    (2, 'Bob',   ['user', 'tester'], [70, 80, 75]);

-- 数组索引（从 0 开始）
SELECT tags[0] FROM users;

-- ARRAY 函数
SELECT SIZE(tags) FROM users;                        -- 或 ARRAY_SIZE
SELECT ARRAY_LENGTH(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT ARRAY_POSITION(tags, 'admin') FROM users;
SELECT ARRAY_SORT(tags) FROM users;
SELECT ARRAY_DISTINCT(tags) FROM users;
SELECT ARRAY_UNION(ARRAY[1,2], ARRAY[2,3]);
SELECT ARRAY_INTERSECT(ARRAY[1,2,3], ARRAY[2,3,4]);
SELECT ARRAY_EXCEPT(ARRAY[1,2,3], ARRAY[2]);
SELECT ARRAY_JOIN(tags, ', ') FROM users;
SELECT ARRAY_PUSHBACK(tags, 'new') FROM users;
SELECT ARRAY_PUSHFRONT(tags, 'first') FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT ARRAY_SLICE(scores, 1, 2) FROM users;
SELECT ARRAY_COMPACT(ARRAY[1, NULL, 2, NULL]);       -- 移除 NULL
SELECT ARRAY_REVERSE(scores) FROM users;
SELECT ARRAYS_OVERLAP(ARRAY[1,2], ARRAY[2,3]);       -- 是否有交集

-- EXPLODE: 展开数组
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- EXPLODE_NUMBERS: 生成序列
SELECT EXPLODE_NUMBERS(5);                           -- 0,1,2,3,4

-- COLLECT_LIST / COLLECT_SET
SELECT COLLECT_LIST(name) FROM users;
SELECT COLLECT_SET(name) FROM users;

-- ARRAY_AGG（Doris 2.0+）
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

-- ============================================================
-- MAP 类型（Doris 2.0+）
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       VARCHAR(100),
    attributes MAP<VARCHAR(50), VARCHAR(200)>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO products VALUES
    (1, 'Laptop', {'brand': 'Dell', 'ram': '16GB'});

-- Map 访问
SELECT attributes['brand'] FROM products;
SELECT element_at(attributes, 'brand') FROM products;

-- Map 函数
SELECT MAP_KEYS(attributes) FROM products;
SELECT MAP_VALUES(attributes) FROM products;
SELECT MAP_SIZE(attributes) FROM products;
SELECT MAP_CONTAINS_KEY(attributes, 'brand') FROM products;
SELECT MAP_CONTAINS_VALUE(attributes, 'Dell') FROM products;

-- Map 展开
SELECT p.name, t.key, t.value
FROM products p
LATERAL VIEW EXPLODE(p.attributes) t AS key, value;

-- ============================================================
-- STRUCT 类型（Doris 2.0+）
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: VARCHAR(100), email: VARCHAR(200)>,
    address  STRUCT<city: VARCHAR(100), zip: VARCHAR(10)>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO orders VALUES
    (1, NAMED_STRUCT('name', 'Alice', 'email', 'a@x.com'),
        NAMED_STRUCT('city', 'NYC', 'zip', '10001'));

-- 访问字段
SELECT customer.name, address.city FROM orders;
SELECT STRUCT_ELEMENT(customer, 'name') FROM orders;
SELECT STRUCT_ELEMENT(customer, 1) FROM orders;

-- ============================================================
-- JSON 类型（Doris 1.2+）
-- ============================================================

CREATE TABLE events (
    id   BIGINT,
    data JSON
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO events VALUES (1, '{"type": "click", "tags": ["a","b"]}');

SELECT json_extract(data, '$.type') FROM events;
SELECT json_extract(data, '$.tags[0]') FROM events;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of STRUCT
CREATE TABLE event_items (
    id    BIGINT,
    items ARRAY<STRUCT<name: VARCHAR(100), qty: INT, price: DOUBLE>>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- MAP of ARRAY（Doris 2.0+）
-- STRUCT 嵌套 STRUCT

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Doris 原生支持 ARRAY (1.2+)、MAP (2.0+)、STRUCT (2.0+)
-- 2. 数组下标从 0 开始
-- 3. LATERAL VIEW EXPLODE 展开数组和 Map
-- 4. COLLECT_LIST/COLLECT_SET 聚合为数组
-- 5. 支持嵌套类型
-- 6. JSON 类型从 1.2 开始支持
