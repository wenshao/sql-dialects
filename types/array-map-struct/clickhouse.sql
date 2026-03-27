-- ClickHouse: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] ClickHouse Documentation - Array
--       https://clickhouse.com/docs/en/sql-reference/data-types/array
--   [2] ClickHouse Documentation - Map
--       https://clickhouse.com/docs/en/sql-reference/data-types/map
--   [3] ClickHouse Documentation - Tuple (Struct)
--       https://clickhouse.com/docs/en/sql-reference/data-types/tuple
--   [4] ClickHouse Documentation - Nested
--       https://clickhouse.com/docs/en/sql-reference/data-types/nested-data-structures/nested
--   [5] ClickHouse Documentation - Array Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/array-functions

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     UInt64,
    name   String,
    tags   Array(String),
    scores Array(UInt32),
    matrix Array(Array(UInt32))              -- 嵌套数组
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO users VALUES
    (1, 'Alice', ['admin', 'dev'], [90, 85, 95], [[1,2],[3,4]]),
    (2, 'Bob',   ['user', 'tester'], [70, 80, 75], [[5,6]]);

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;                   -- 第一个元素

-- ============================================================
-- ARRAY 函数（ClickHouse 提供非常丰富的数组函数）
-- ============================================================

-- 基本函数
SELECT length(tags) FROM users;              -- 长度 (= arrayLength 的别名)
SELECT empty(tags) FROM users;               -- 是否为空
SELECT notEmpty(tags) FROM users;

-- 元素操作
SELECT arrayElement(tags, 1) FROM users;     -- 等价于 tags[1]
SELECT has(tags, 'admin') FROM users;        -- 包含检查
SELECT hasAll(tags, ['admin', 'dev']) FROM users;
SELECT hasAny(tags, ['admin', 'user']) FROM users;

-- indexOf: 查找位置
SELECT indexOf(tags, 'admin') FROM users;    -- 返回 0 表示未找到

-- 排序
SELECT arraySort(scores) FROM users;
SELECT arrayReverseSort(scores) FROM users;

-- 去重
SELECT arrayDistinct(tags) FROM users;

-- 展平
SELECT arrayFlatten([[1,2],[3,4]]);          -- [1,2,3,4]

-- 追加/连接
SELECT arrayPushBack(tags, 'new') FROM users;
SELECT arrayPushFront(tags, 'first') FROM users;
SELECT arrayConcat(tags, ['extra']) FROM users;

-- 删除
SELECT arrayPopBack(scores) FROM users;      -- 删除最后一个
SELECT arrayPopFront(scores) FROM users;     -- 删除第一个
SELECT arrayFilter(x -> x > 80, scores) FROM users;  -- 过滤

-- 切片
SELECT arraySlice(scores, 1, 2) FROM users;  -- 从位置 1 取 2 个元素

-- 转换
SELECT arrayMap(x -> x * 2, scores) FROM users;
SELECT arrayReduce('sum', scores) FROM users;
SELECT arrayStringConcat(tags, ', ') FROM users;

-- 集合操作
SELECT arrayIntersect([1,2,3], [2,3,4]);     -- [2,3]
SELECT arrayUnion([1,2], [2,3]);             -- [1,2,3] (ClickHouse 22.3+)
SELECT arrayDifference([1,3,6,10]);          -- [0,2,3,4]

-- 统计
SELECT arraySum(scores) FROM users;
SELECT arrayAvg(scores) FROM users;
SELECT arrayMin(scores) FROM users;
SELECT arrayMax(scores) FROM users;

-- ============================================================
-- ARRAY JOIN（= UNNEST 的 ClickHouse 等价物）
-- ============================================================

-- ARRAY JOIN: 展开数组为行（类似 UNNEST / LATERAL VIEW EXPLODE）
SELECT id, name, tag
FROM users
ARRAY JOIN tags AS tag;

-- LEFT ARRAY JOIN: 保留空数组的行
SELECT id, name, tag
FROM users
LEFT ARRAY JOIN tags AS tag;

-- 多数组同时展开
SELECT id, tag, score
FROM users
ARRAY JOIN tags AS tag, scores AS score;

-- ============================================================
-- groupArray: 聚合为数组（= ARRAY_AGG）
-- ============================================================

SELECT department, groupArray(name) AS members
FROM employees
GROUP BY department;

-- 去重
SELECT groupUniqArray(name) FROM employees;

-- 限制数量
SELECT groupArray(10)(name) FROM employees;

-- ============================================================
-- MAP 类型（ClickHouse 21.1+）
-- ============================================================

CREATE TABLE products (
    id         UInt64,
    name       String,
    attributes Map(String, String),
    metrics    Map(String, Float64)
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO products VALUES
    (1, 'Laptop', {'brand': 'Dell', 'ram': '16GB', 'cpu': 'i7'}, {'price': 999.99, 'weight': 2.1}),
    (2, 'Phone',  {'brand': 'Apple', 'storage': '128GB'}, {'price': 799.99, 'weight': 0.2});

-- 访问 Map 值
SELECT attributes['brand'] FROM products;

-- Map 函数
SELECT mapKeys(attributes) FROM products;      -- 所有键
SELECT mapValues(attributes) FROM products;    -- 所有值
SELECT mapContains(attributes, 'ram') FROM products;

-- Map 操作（ClickHouse 22.3+）
SELECT mapApply((k, v) -> (k, upper(v)), attributes) FROM products;
SELECT mapFilter((k, v) -> k = 'brand', attributes) FROM products;

-- mapFromArrays: 从两个数组构造 Map
SELECT mapFromArrays(['a','b','c'], [1,2,3]);

-- ============================================================
-- Tuple 类型（类似 STRUCT）
-- ============================================================

CREATE TABLE orders (
    id       UInt64,
    customer Tuple(name String, email String),
    address  Tuple(street String, city String, state String, zip String)
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO orders VALUES
    (1, ('Alice', 'alice@example.com'), ('123 Main St', 'Springfield', 'IL', '62701'));

-- 访问 Tuple 字段（按位置或按名称）
SELECT customer.1 FROM orders;               -- 按位置（从 1 开始）
SELECT customer.name FROM orders;            -- 按名称（命名 Tuple）

-- Tuple 构造
SELECT tuple('Alice', 30) AS t;
SELECT (1, 'text', true) AS t;

-- untuple: 展开 Tuple 为独立列
SELECT untuple(customer) FROM orders;

-- ============================================================
-- Nested 类型（ClickHouse 特有）
-- ============================================================

-- Nested 是 Array of Struct 的语法糖
CREATE TABLE events (
    id     UInt64,
    items  Nested(
        product_id UInt64,
        name       String,
        quantity   UInt32,
        price      Float64
    )
) ENGINE = MergeTree() ORDER BY id;

-- Nested 实际存储为多个并行数组
-- items.product_id Array(UInt64), items.name Array(String), ...

INSERT INTO events VALUES
    (1, [1, 2], ['Widget', 'Gadget'], [2, 1], [9.99, 29.99]);

-- 访问
SELECT items.name, items.price FROM events;

-- 展开
SELECT id, item_name, item_price
FROM events
ARRAY JOIN items.name AS item_name, items.price AS item_price;

-- ============================================================
-- JSON 类型（ClickHouse 22.3+, 实验性）
-- ============================================================

CREATE TABLE logs (
    id   UInt64,
    data JSON
) ENGINE = MergeTree() ORDER BY id;

-- 或者使用更成熟的 String + JSON 函数
SELECT JSONExtractString('{"name":"Alice"}', 'name');
SELECT JSONExtractInt('{"age":30}', 'age');
SELECT JSONExtractArrayRaw('{"tags":["a","b"]}', 'tags');

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. ClickHouse 原生支持 Array、Map、Tuple、Nested
-- 2. 数组函数非常丰富（50+函数）
-- 3. ARRAY JOIN 是展开数组的主要方式
-- 4. Map 类型从 21.1 版本开始支持
-- 5. Nested 实际是多个并行数组的语法糖
-- 6. 支持嵌套数组 Array(Array(...))
-- 7. JSON 类型仍在实验阶段
