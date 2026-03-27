-- Spark SQL: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Spark SQL Documentation - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html
--   [2] Spark SQL Documentation - Array Functions
--       https://spark.apache.org/docs/latest/api/sql/index.html#array-functions
--   [3] Spark SQL Documentation - Map Functions
--       https://spark.apache.org/docs/latest/api/sql/index.html#map-functions
--   [4] Spark SQL Documentation - Struct Functions
--       https://spark.apache.org/docs/latest/api/sql/index.html#struct-functions

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>,
    matrix ARRAY<ARRAY<INT>>                  -- 嵌套数组
) USING DELTA;

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95), ARRAY(ARRAY(1,2), ARRAY(3,4))),
    (2, 'Bob',   ARRAY('user', 'tester'), ARRAY(70, 80, 75), ARRAY(ARRAY(5,6)));

-- 数组索引（从 0 开始）
SELECT tags[0] FROM users;
SELECT element_at(tags, 1) FROM users;        -- 从 1 开始

-- ============================================================
-- ARRAY 函数（Spark 提供非常丰富的数组函数）
-- ============================================================

-- 基本函数
SELECT SIZE(tags) FROM users;                 -- 长度
SELECT CARDINALITY(tags) FROM users;          -- 同 SIZE

-- 包含检查
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT EXISTS(scores, x -> x > 80) FROM users;     -- Lambda 检查（Spark 3.0+）
SELECT FORALL(scores, x -> x > 60) FROM users;     -- 全部满足

-- 排序
SELECT SORT_ARRAY(scores) FROM users;                -- 升序
SELECT SORT_ARRAY(scores, false) FROM users;         -- 降序
SELECT ARRAY_SORT(tags) FROM users;                  -- Spark 3.0+

-- 去重/集合操作
SELECT ARRAY_DISTINCT(ARRAY(1, 2, 2, 3));
SELECT ARRAY_UNION(ARRAY(1, 2), ARRAY(2, 3));
SELECT ARRAY_INTERSECT(ARRAY(1, 2, 3), ARRAY(2, 3, 4));
SELECT ARRAY_EXCEPT(ARRAY(1, 2, 3), ARRAY(2));

-- 追加/连接
SELECT ARRAY_APPEND(tags, 'new') FROM users;          -- Spark 3.4+
SELECT ARRAY_PREPEND(tags, 'first') FROM users;       -- Spark 3.4+
SELECT CONCAT(tags, ARRAY('extra')) FROM users;
SELECT FLATTEN(matrix) FROM users;                    -- 展平嵌套数组

-- 位置/搜索
SELECT ARRAY_POSITION(tags, 'admin') FROM users;      -- 返回位置（从 1 开始）
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;

-- 高阶函数（Spark 2.4+）
SELECT TRANSFORM(scores, x -> x * 2) FROM users;     -- MAP 操作
SELECT FILTER(scores, x -> x > 80) FROM users;       -- 过滤
SELECT AGGREGATE(scores, 0, (acc, x) -> acc + x) FROM users;  -- REDUCE
SELECT ZIP_WITH(tags, scores, (t, s) -> STRUCT(t, s)) FROM users;

-- 转换
SELECT ARRAY_JOIN(tags, ', ') FROM users;             -- 转为字符串
SELECT SEQUENCE(1, 10) AS nums;                       -- 生成序列
SELECT SEQUENCE(DATE'2024-01-01', DATE'2024-01-07') AS dates;

-- 切片
SELECT SLICE(scores, 1, 2) FROM users;               -- 从位置 1 取 2 个

-- ============================================================
-- EXPLODE / LATERAL VIEW: 展开数组为行（= UNNEST）
-- ============================================================

-- EXPLODE
SELECT id, name, EXPLODE(tags) AS tag FROM users;

-- LATERAL VIEW
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER
SELECT u.name, t.tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- POSEXPLODE: 带位置
SELECT u.name, t.pos, t.tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- INLINE: 展开 STRUCT 数组
-- SELECT id, INLINE(items) FROM events;

-- ============================================================
-- COLLECT_LIST / COLLECT_SET: 聚合为数组
-- ============================================================

SELECT department, COLLECT_LIST(name) AS members FROM employees GROUP BY department;
SELECT department, COLLECT_SET(name) AS unique_members FROM employees GROUP BY department;

-- ARRAY_AGG（Spark 3.3+）
SELECT department, ARRAY_AGG(name) AS members FROM employees GROUP BY department;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
) USING DELTA;

INSERT INTO products VALUES
    (1, 'Laptop', MAP('brand', 'Dell', 'ram', '16GB'), MAP('price', 999.99, 'weight', 2.1));

-- Map 访问
SELECT attributes['brand'] FROM products;
SELECT element_at(attributes, 'brand') FROM products;

-- Map 函数
SELECT MAP_KEYS(attributes) FROM products;
SELECT MAP_VALUES(attributes) FROM products;
SELECT SIZE(attributes) FROM products;
SELECT MAP_ENTRIES(attributes) FROM products;    -- Spark 3.0+

-- Map 构造
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT MAP_FROM_ARRAYS(ARRAY('a', 'b'), ARRAY(1, 2));
SELECT MAP_FROM_ENTRIES(ARRAY(STRUCT('a', 1), STRUCT('b', 2)));
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');

-- Map 操作
SELECT MAP_CONCAT(MAP('a', 1), MAP('b', 2));     -- 合并
SELECT MAP_FILTER(attributes, (k, v) -> k = 'brand') FROM products;  -- Spark 3.0+
SELECT TRANSFORM_KEYS(attributes, (k, v) -> UPPER(k)) FROM products;
SELECT TRANSFORM_VALUES(metrics, (k, v) -> v * 1.1) FROM products;

-- Map 展开
SELECT p.name, mk.key, mk.value
FROM products p
LATERAL VIEW EXPLODE(p.attributes) mk AS key, value;

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<street: STRING, city: STRING, state: STRING, zip: STRING>
) USING DELTA;

INSERT INTO orders VALUES (
    1,
    STRUCT('Alice', 'alice@example.com'),
    STRUCT('123 Main St', 'Springfield', 'IL', '62701')
);

-- 访问字段
SELECT customer.name, address.city FROM orders;

-- STRUCT 构造
SELECT STRUCT('Alice', 30) AS s;
SELECT NAMED_STRUCT('name', 'Alice', 'age', 30) AS s;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of STRUCT
CREATE TABLE events (
    id    BIGINT,
    items ARRAY<STRUCT<product_id: BIGINT, name: STRING, qty: INT, price: DOUBLE>>
) USING DELTA;

-- INLINE: 展开 STRUCT 数组
SELECT id, inline(items) FROM events;

-- MAP of ARRAY
CREATE TABLE configs (
    id       BIGINT,
    settings MAP<STRING, ARRAY<STRING>>
) USING DELTA;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Spark SQL 原生支持 ARRAY、MAP、STRUCT
-- 2. 高阶函数 (TRANSFORM, FILTER, AGGREGATE) 从 Spark 2.4+ 可用
-- 3. ARRAY 下标从 0 开始
-- 4. EXPLODE/LATERAL VIEW 展开数组和 Map
-- 5. 支持任意深度的嵌套
-- 6. Delta Lake/Parquet/ORC 对复杂类型有良好支持
