-- DuckDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] DuckDB Documentation - List Type
--       https://duckdb.org/docs/sql/data_types/list.html
--   [2] DuckDB Documentation - Map Type
--       https://duckdb.org/docs/sql/data_types/map.html
--   [3] DuckDB Documentation - Struct Type
--       https://duckdb.org/docs/sql/data_types/struct.html
--   [4] DuckDB Documentation - UNION Type
--       https://duckdb.org/docs/sql/data_types/union.html
--   [5] DuckDB Documentation - List Functions
--       https://duckdb.org/docs/sql/functions/list.html

-- ============================================================
-- LIST 类型（DuckDB 中的数组）
-- ============================================================

CREATE TABLE users (
    id     INTEGER PRIMARY KEY,
    name   VARCHAR NOT NULL,
    tags   VARCHAR[],                          -- LIST 类型
    scores INTEGER[]
);

INSERT INTO users VALUES
    (1, 'Alice', ['admin', 'dev'], [90, 85, 95]),
    (2, 'Bob',   ['user', 'tester'], [70, 80, 75]);

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;                    -- 第一个元素
SELECT list_extract(tags, 1) FROM users;      -- 等价

-- ============================================================
-- LIST 函数
-- ============================================================

-- 长度
SELECT len(tags) FROM users;
SELECT list_count(tags) FROM users;

-- 包含检查
SELECT list_contains(tags, 'admin') FROM users;
SELECT list_has(tags, 'admin') FROM users;    -- 别名

-- 排序
SELECT list_sort(scores) FROM users;
SELECT list_reverse_sort(scores) FROM users;

-- 去重/集合操作
SELECT list_distinct(tags) FROM users;
SELECT list_union(['a','b'], ['b','c']);
SELECT list_intersect([1,2,3], [2,3,4]);

-- 追加/连接
SELECT list_append(tags, 'new') FROM users;
SELECT list_prepend('first', tags) FROM users;
SELECT list_concat(tags, ['extra']) FROM users;
SELECT flatten([[1,2],[3,4]]);                -- [1,2,3,4]

-- 位置/搜索
SELECT list_position(tags, 'admin') FROM users;
SELECT list_indexof(tags, 'admin') FROM users; -- 别名

-- 切片
SELECT tags[1:2] FROM users;                  -- 切片语法
SELECT list_slice(tags, 1, 2) FROM users;

-- 聚合 LIST 函数
SELECT list_sum(scores) FROM users;
SELECT list_avg(scores) FROM users;
SELECT list_min(scores) FROM users;
SELECT list_max(scores) FROM users;

-- 高阶函数
SELECT list_transform(scores, x -> x * 2) FROM users;
SELECT list_filter(scores, x -> x > 80) FROM users;
SELECT list_reduce(scores, (acc, x) -> acc + x) FROM users;
SELECT list_any_value(tags) FROM users;

-- 转换
SELECT list_string(tags, ', ') FROM users;    -- 转为字符串
SELECT string_split('a,b,c', ',');            -- 字符串转列表

-- 范围生成
SELECT range(1, 10);                          -- [1,2,...,9]
SELECT generate_series(1, 5);                 -- [1,2,3,4,5]

-- ============================================================
-- UNNEST: 展开 LIST 为行
-- ============================================================

SELECT UNNEST(['a','b','c']) AS val;

-- 与表关联
SELECT u.name, UNNEST(u.tags) AS tag FROM users u;

-- 带序号
SELECT u.name, UNNEST(u.tags) AS tag, generate_subscripts(u.tags, 1) AS idx
FROM users u;

-- ============================================================
-- LIST_AGG / ARRAY_AGG: 聚合为列表
-- ============================================================

SELECT department, list(name ORDER BY name) AS members
FROM employees
GROUP BY department;

SELECT department, array_agg(name) AS members
FROM employees
GROUP BY department;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE TABLE products (
    id         INTEGER PRIMARY KEY,
    name       VARCHAR,
    attributes MAP(VARCHAR, VARCHAR),
    metrics    MAP(VARCHAR, DOUBLE)
);

INSERT INTO products VALUES
    (1, 'Laptop', MAP {'brand': 'Dell', 'ram': '16GB'}, MAP {'price': 999.99, 'weight': 2.1}),
    (2, 'Phone',  MAP {'brand': 'Apple'}, MAP {'price': 799.99});

-- Map 访问
SELECT attributes['brand'] FROM products;
SELECT element_at(attributes, 'brand') FROM products;

-- Map 函数
SELECT map_keys(attributes) FROM products;
SELECT map_values(attributes) FROM products;
SELECT map_entries(attributes) FROM products;
SELECT cardinality(attributes) FROM products;

-- Map 构造
SELECT MAP {'a': 1, 'b': 2};
SELECT map_from_entries([('a', 1), ('b', 2)]);

-- Map 包含
SELECT map_contains(attributes, 'brand') FROM products;

-- Map 提取（获取子 Map）
SELECT map_extract(attributes, 'brand') FROM products;

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       INTEGER PRIMARY KEY,
    customer STRUCT(name VARCHAR, email VARCHAR),
    address  STRUCT(street VARCHAR, city VARCHAR, state VARCHAR, zip VARCHAR)
);

INSERT INTO orders VALUES (
    1,
    {'name': 'Alice', 'email': 'alice@example.com'},
    {'street': '123 Main St', 'city': 'Springfield', 'state': 'IL', 'zip': '62701'}
);

-- 访问 STRUCT 字段
SELECT customer.name, address.city FROM orders;

-- STRUCT 构造
SELECT {'name': 'Alice', 'age': 30} AS person;
SELECT struct_pack(name := 'Alice', age := 30);
SELECT row('Alice', 30);

-- struct_extract
SELECT struct_extract(customer, 'name') FROM orders;

-- ============================================================
-- UNION 类型（DuckDB 特有的标记联合）
-- ============================================================

CREATE TABLE mixed_data (
    id    INTEGER,
    value UNION(str VARCHAR, num INTEGER, flag BOOLEAN)
);

INSERT INTO mixed_data VALUES (1, 'hello'), (2, 42), (3, true);

SELECT id, union_tag(value) AS type, value FROM mixed_data;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- LIST of STRUCT
CREATE TABLE events (
    id    INTEGER PRIMARY KEY,
    items STRUCT(product_id INTEGER, name VARCHAR, qty INTEGER, price DOUBLE)[]
);

INSERT INTO events VALUES (1, [
    {'product_id': 1, 'name': 'Widget', 'qty': 2, 'price': 9.99},
    {'product_id': 2, 'name': 'Gadget', 'qty': 1, 'price': 29.99}
]);

-- 查询嵌套
SELECT id, UNNEST(items) FROM events;

-- MAP of LIST
CREATE TABLE configs (
    id       INTEGER,
    settings MAP(VARCHAR, VARCHAR[])
);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. DuckDB 原生支持 LIST、MAP、STRUCT、UNION
-- 2. LIST 下标从 1 开始
-- 3. 提供丰富的高阶函数 (list_transform, list_filter, list_reduce)
-- 4. 支持任意深度的嵌套
-- 5. MAP 使用花括号语法 MAP {'key': 'value'}
-- 6. STRUCT 使用花括号语法 {'field': value}
-- 7. UNION 类型是 DuckDB 独有的特性
