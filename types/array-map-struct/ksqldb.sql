-- ksqlDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] ksqlDB Documentation - Data Types (ARRAY)
--       https://docs.ksqldb.io/en/latest/reference/sql/data-types/#array
--   [2] ksqlDB Documentation - Data Types (MAP)
--       https://docs.ksqldb.io/en/latest/reference/sql/data-types/#map
--   [3] ksqlDB Documentation - Data Types (STRUCT)
--       https://docs.ksqldb.io/en/latest/reference/sql/data-types/#struct

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE STREAM users (
    id     BIGINT KEY,
    name   VARCHAR,
    tags   ARRAY<VARCHAR>,
    scores ARRAY<INT>
) WITH (
    KAFKA_TOPIC = 'users',
    VALUE_FORMAT = 'JSON'
);

-- 数组构造
SELECT ARRAY['admin', 'dev'] AS tags FROM users;

-- 数组索引（从 1 开始）
SELECT tags[1] AS first_tag FROM users;

-- ARRAY 函数
SELECT ARRAY_LENGTH(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;
SELECT ARRAY_DISTINCT(tags) FROM users;
SELECT ARRAY_UNION(ARRAY[1,2], ARRAY[2,3]) FROM users;
SELECT ARRAY_INTERSECT(ARRAY[1,2,3], ARRAY[2,3,4]) FROM users;
SELECT ARRAY_EXCEPT(ARRAY[1,2,3], ARRAY[2]) FROM users;
SELECT ARRAY_JOIN(tags, ', ') FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT ARRAY_SORT(tags) FROM users;

-- EXPLODE: 展开数组为行
SELECT id, name, EXPLODE(tags) AS tag FROM users;

-- COLLECT_LIST / COLLECT_SET
SELECT COLLECT_LIST(name) FROM users GROUP BY 1;
SELECT COLLECT_SET(name) FROM users GROUP BY 1;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE STREAM products (
    id         BIGINT KEY,
    name       VARCHAR,
    attributes MAP<VARCHAR, VARCHAR>
) WITH (
    KAFKA_TOPIC = 'products',
    VALUE_FORMAT = 'JSON'
);

-- Map 构造
SELECT MAP('brand' := 'Dell', 'ram' := '16GB') AS attrs FROM products;

-- Map 访问
SELECT attributes['brand'] FROM products;

-- MAP 函数
SELECT MAP_KEYS(attributes) FROM products;     -- 返回 ARRAY
SELECT MAP_VALUES(attributes) FROM products;   -- 返回 ARRAY
SELECT MAP_UNION(MAP('a' := 1), MAP('b' := 2)) FROM products;

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE STREAM orders (
    id       BIGINT KEY,
    customer STRUCT<name VARCHAR, email VARCHAR>,
    address  STRUCT<street VARCHAR, city VARCHAR, state VARCHAR, zip VARCHAR>
) WITH (
    KAFKA_TOPIC = 'orders',
    VALUE_FORMAT = 'JSON'
);

-- 访问 STRUCT 字段
SELECT customer->name, customer->email FROM orders;
SELECT address->city FROM orders;

-- STRUCT 构造
SELECT STRUCT(name := 'Alice', email := 'alice@example.com') FROM orders;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of STRUCT
CREATE STREAM events (
    id    BIGINT KEY,
    items ARRAY<STRUCT<name VARCHAR, qty INT, price DOUBLE>>
) WITH (
    KAFKA_TOPIC = 'events',
    VALUE_FORMAT = 'JSON'
);

-- 访问嵌套
SELECT items[1]->name FROM events;

-- EXPLODE 嵌套
SELECT EXPLODE(items)->name AS item_name FROM events;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. ksqlDB 原生支持 ARRAY、MAP、STRUCT
-- 2. 数组下标从 1 开始
-- 3. STRUCT 字段使用 -> 访问（非点号）
-- 4. MAP 构造使用 := 而非 =>
-- 5. EXPLODE 展开数组为行
-- 6. 与 Kafka 的 JSON/Avro/Protobuf 格式无缝映射
