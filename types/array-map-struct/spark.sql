-- Spark SQL: 复合类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html
--   [2] Spark SQL - Collection Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html

-- ============================================================
-- 1. ARRAY 类型
-- ============================================================
CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>,
    matrix ARRAY<ARRAY<INT>>                     -- 嵌套数组
) USING DELTA;

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin','dev'), ARRAY(90,85,95), ARRAY(ARRAY(1,2),ARRAY(3,4)));

-- 数组访问（下标从 0 开始）
SELECT tags[0] FROM users;
SELECT element_at(tags, 1) FROM users;           -- 从 1 开始（SQL 标准）

-- 设计分析: Spark 的复合类型是其与传统数据库的最大差异之一
--   传统数据库: 第一范式（1NF），一列一值，数组通过关联表实现
--   Spark:      原生 ARRAY/MAP/STRUCT，一列可以存储复合结构
--   这源自 Spark 的数据湖定位——半结构化数据（JSON/Avro/Parquet）天然包含嵌套结构
--
-- 对比:
--   PostgreSQL: 支持 ARRAY 类型（但不支持 MAP/STRUCT 作为列类型）
--   MySQL:      不支持 ARRAY 列类型（用 JSON 替代）
--   BigQuery:   ARRAY + STRUCT（与 Spark 最相似）
--   ClickHouse: Array + Tuple + Map（类似 Spark）
--   Hive:       ARRAY/MAP/STRUCT（Spark 继承自 Hive）

-- ============================================================
-- 2. ARRAY 函数
-- ============================================================
SELECT SIZE(tags), CARDINALITY(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT EXISTS(scores, x -> x > 80) FROM users;          -- Lambda (3.0+)
SELECT FORALL(scores, x -> x > 60) FROM users;
SELECT SORT_ARRAY(scores) FROM users;
SELECT ARRAY_DISTINCT(ARRAY(1, 2, 2, 3));
SELECT ARRAY_UNION(ARRAY(1,2), ARRAY(2,3));
SELECT ARRAY_INTERSECT(ARRAY(1,2,3), ARRAY(2,3,4));
SELECT ARRAY_EXCEPT(ARRAY(1,2,3), ARRAY(2));
SELECT ARRAY_APPEND(tags, 'new') FROM users;             -- 3.4+
SELECT CONCAT(tags, ARRAY('extra')) FROM users;
SELECT FLATTEN(matrix) FROM users;
SELECT ARRAY_POSITION(tags, 'admin') FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT ARRAY_JOIN(tags, ', ') FROM users;
SELECT SEQUENCE(1, 10) AS nums;
SELECT SLICE(scores, 1, 2) FROM users;

-- ============================================================
-- 3. 高阶函数（Spark 2.4+）
-- ============================================================
SELECT TRANSFORM(scores, x -> x * 2) FROM users;        -- MAP 操作
SELECT FILTER(scores, x -> x > 80) FROM users;           -- 过滤
SELECT AGGREGATE(scores, 0, (acc, x) -> acc + x) FROM users; -- REDUCE
SELECT ZIP_WITH(tags, scores, (t, s) -> STRUCT(t, s)) FROM users;

-- 高阶函数是 Spark SQL 的独特能力:
--   传统 SQL 没有 Lambda 表达式——处理数组需要 UNNEST/LATERAL VIEW
--   Spark 的高阶函数直接在数组上操作，无需展开为行再聚合回来
--   对比: BigQuery 也支持类似的 Lambda（ARRAY_TRANSFORM 等）

-- ============================================================
-- 4. EXPLODE / LATERAL VIEW: 展开为行
-- ============================================================
SELECT id, name, EXPLODE(tags) AS tag FROM users;

SELECT u.name, t.tag FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

SELECT u.name, t.tag FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;             -- 保留空数组行

SELECT u.name, t.pos, t.tag FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;            -- 带位置

-- COLLECT_LIST / COLLECT_SET: 行聚合回数组
SELECT department, COLLECT_LIST(name) FROM employees GROUP BY department;
SELECT department, COLLECT_SET(name) FROM employees GROUP BY department;

-- ============================================================
-- 5. MAP 类型
-- ============================================================
CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
) USING DELTA;

INSERT INTO products VALUES
    (1, 'Laptop', MAP('brand','Dell','ram','16GB'), MAP('price',999.99,'weight',2.1));

SELECT attributes['brand'] FROM products;
SELECT MAP_KEYS(attributes), MAP_VALUES(attributes) FROM products;
SELECT SIZE(attributes), MAP_ENTRIES(attributes) FROM products;

-- Map 构造
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT MAP_FROM_ARRAYS(ARRAY('a','b'), ARRAY(1,2));
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');

-- Map 高阶函数
SELECT MAP_FILTER(attributes, (k, v) -> k = 'brand') FROM products;
SELECT TRANSFORM_KEYS(attributes, (k, v) -> UPPER(k)) FROM products;
SELECT TRANSFORM_VALUES(metrics, (k, v) -> v * 1.1) FROM products;
SELECT MAP_CONCAT(MAP('a', 1), MAP('b', 2));

-- Map 展开
SELECT p.name, mk.key, mk.value FROM products p
LATERAL VIEW EXPLODE(p.attributes) mk AS key, value;

-- ============================================================
-- 6. STRUCT 类型
-- ============================================================
CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<street: STRING, city: STRING, zip: STRING>
) USING DELTA;

INSERT INTO orders VALUES (
    1, STRUCT('Alice', 'alice@example.com'),
    STRUCT('123 Main St', 'Springfield', '62701')
);

SELECT customer.name, address.city FROM orders;
SELECT STRUCT('Alice', 30) AS s;
SELECT NAMED_STRUCT('name', 'Alice', 'age', 30) AS s;

-- STRUCT 数组展开
-- CREATE TABLE events (id BIGINT, items ARRAY<STRUCT<name:STRING, qty:INT>>) USING DELTA;
-- SELECT id, inline(items) FROM events;

-- ============================================================
-- 7. 嵌套类型组合
-- ============================================================
CREATE TABLE configs (
    id       BIGINT,
    settings MAP<STRING, ARRAY<STRING>>          -- Map of Arrays
) USING DELTA;

-- 任意深度嵌套: Parquet/ORC/Delta 对复杂类型有良好支持

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Spark 2.0: ARRAY, MAP, STRUCT, EXPLODE, LATERAL VIEW
-- Spark 2.4: 高阶函数 (TRANSFORM, FILTER, AGGREGATE)
-- Spark 3.0: EXISTS, FORALL, MAP_FILTER, TRANSFORM_KEYS/VALUES
-- Spark 3.3: ARRAY_AGG
-- Spark 3.4: ARRAY_APPEND, ARRAY_PREPEND
--
-- 限制:
--   ARRAY 下标从 0 开始（element_at 从 1 开始——容易混淆）
--   COLLECT_LIST/SET 在大分组上可能 OOM（数据收集到单个 Executor 内存）
--   嵌套类型的 Schema Evolution 在不同格式中支持程度不同
--   高阶函数是 Spark 特有语法（迁移到其他引擎需重写为 UNNEST + 聚合）
