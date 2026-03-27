-- StarRocks: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] StarRocks Documentation - ARRAY
--       https://docs.starrocks.io/docs/sql-reference/data-types/semi_structured/Array/
--   [2] StarRocks Documentation - MAP
--       https://docs.starrocks.io/docs/sql-reference/data-types/semi_structured/Map/
--   [3] StarRocks Documentation - STRUCT
--       https://docs.starrocks.io/docs/sql-reference/data-types/semi_structured/Struct/
--   [4] StarRocks Documentation - JSON
--       https://docs.starrocks.io/docs/sql-reference/data-types/semi_structured/JSON/

-- ============================================================
-- ARRAY 类型（StarRocks 1.19+）
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

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;

-- ARRAY 函数
SELECT array_length(tags) FROM users;
SELECT array_contains(tags, 'admin') FROM users;
SELECT array_position(tags, 'admin') FROM users;
SELECT array_sort(tags) FROM users;
SELECT array_distinct(tags) FROM users;
SELECT array_join(tags, ', ') FROM users;
SELECT array_append(tags, 'new') FROM users;
SELECT array_remove(tags, 'admin') FROM users;
SELECT array_slice(scores, 1, 2) FROM users;
SELECT array_concat(tags, ['extra']) FROM users;
SELECT arrays_overlap(tags, ['admin', 'user']) FROM users;
SELECT array_intersect(ARRAY[1,2,3], ARRAY[2,3,4]);
SELECT array_difference(ARRAY[1,2,3], ARRAY[2]);

-- 高阶函数
SELECT array_map(tags, x -> upper(x)) FROM users;
SELECT array_filter(scores, x -> x > 80) FROM users;
SELECT all_match(scores, x -> x > 60) FROM users;
SELECT any_match(scores, x -> x > 80) FROM users;

-- UNNEST: 展开数组
SELECT u.name, t.tag
FROM users u, unnest(u.tags) AS t(tag);

-- array_agg: 聚合
SELECT department, array_agg(name ORDER BY name)
FROM employees GROUP BY department;

-- ============================================================
-- MAP 类型（StarRocks 3.1+）
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       VARCHAR(100),
    attributes MAP<VARCHAR(50), VARCHAR(200)>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO products VALUES
    (1, 'Laptop', map{'brand': 'Dell', 'ram': '16GB'});

SELECT attributes['brand'] FROM products;
SELECT map_keys(attributes) FROM products;
SELECT map_values(attributes) FROM products;
SELECT map_size(attributes) FROM products;
SELECT map_filter(attributes, (k, v) -> k = 'brand') FROM products;
SELECT transform_keys(attributes, (k, v) -> upper(k)) FROM products;
SELECT transform_values(attributes, (k, v) -> concat(v, '!')) FROM products;

-- Map 展开
SELECT p.name, t.key, t.value
FROM products p, unnest(p.attributes) AS t(key, value);

-- map_agg
SELECT map_agg(name, salary) FROM employees;

-- ============================================================
-- STRUCT 类型（StarRocks 3.1+）
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name VARCHAR(100), email VARCHAR(200)>
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO orders VALUES
    (1, row('Alice', 'alice@example.com'));

SELECT customer.name FROM orders;

-- ============================================================
-- JSON 类型
-- ============================================================

CREATE TABLE events (id BIGINT, data JSON)
DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 8;

INSERT INTO events VALUES (1, parse_json('{"type":"click","tags":["a","b"]}'));
SELECT json_query(data, '$.type') FROM events;
SELECT get_json_string(data, '$.type') FROM events;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. ARRAY (1.19+), MAP (3.1+), STRUCT (3.1+)
-- 2. 数组下标从 1 开始（与 Doris 不同）
-- 3. 支持高阶函数 (array_map, array_filter)
-- 4. unnest 展开数组和 Map
-- 5. JSON 类型也原生支持
