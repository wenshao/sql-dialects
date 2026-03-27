-- Databricks SQL: JSON 类型
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- Databricks 使用 STRING 存储 JSON，或使用原生复合类型
-- 原生复合类型：STRUCT、MAP、ARRAY（推荐，性能更好）
-- STRING + JSON 函数（灵活，适合非结构化数据）

-- ============================================================
-- 原生复合类型（推荐）
-- ============================================================

CREATE TABLE users (
    id       BIGINT GENERATED ALWAYS AS IDENTITY,
    name     STRING,
    address  STRUCT<street: STRING, city: STRING, zip: STRING>,
    tags     ARRAY<STRING>,
    metadata MAP<STRING, STRING>
);

-- 访问 STRUCT 字段
SELECT address.city FROM users;

-- 访问 ARRAY 元素
SELECT tags[0] FROM users;

-- 访问 MAP 元素
SELECT metadata['key1'] FROM users;

-- 展开 ARRAY
SELECT name, tag FROM users LATERAL VIEW EXPLODE(tags) t AS tag;

-- 展开 MAP
SELECT name, key, value FROM users LATERAL VIEW EXPLODE(metadata) t AS key, value;

-- ============================================================
-- JSON 字符串函数
-- ============================================================

CREATE TABLE events (
    id   BIGINT GENERATED ALWAYS AS IDENTITY,
    data STRING                              -- JSON 字符串
);

INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip"]}');

-- 从 JSON 提取
SELECT GET_JSON_OBJECT(data, '$.name') FROM events;          -- 'alice'
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events;       -- 'vip'

-- JSON Path 提取（推荐，更强大）
SELECT data:name FROM events;                -- 使用冒号语法（Databricks 特有）
SELECT data:tags[0] FROM events;

-- FROM_JSON（JSON 字符串 → STRUCT）
SELECT FROM_JSON(data, 'STRUCT<name: STRING, age: INT, tags: ARRAY<STRING>>') AS parsed
FROM events;

-- FROM_JSON + Schema 推断
SELECT FROM_JSON(data, SCHEMA_OF_JSON('{"name": "alice", "age": 25}')) AS parsed
FROM events;

-- TO_JSON（STRUCT → JSON 字符串）
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));
-- 结果: '{"name":"alice","age":25}'

-- JSON_TUPLE（提取多个字段）
SELECT id, json_tuple.*
FROM events
LATERAL VIEW JSON_TUPLE(data, 'name', 'age') json_tuple AS name, age;

-- ============================================================
-- JSON 数组函数
-- ============================================================

SELECT JSON_ARRAY_LENGTH('[1, 2, 3]');       -- 3
SELECT SIZE(ARRAY(1, 2, 3));                 -- 3

-- ============================================================
-- VARIANT 类型（Databricks 2024+）
-- ============================================================
-- 原生半结构化类型，类似 Snowflake 的 VARIANT

CREATE TABLE events_v2 (
    id   BIGINT GENERATED ALWAYS AS IDENTITY,
    data VARIANT
);

-- VARIANT 类型操作
-- INSERT INTO events_v2 (data) VALUES (PARSE_JSON('{"name": "alice"}'));
-- SELECT data:name::STRING FROM events_v2;

-- ============================================================
-- JSON 构造
-- ============================================================

-- 构造 JSON 对象
SELECT TO_JSON(NAMED_STRUCT('name', username, 'age', age)) FROM users;

-- 构造 JSON 数组
SELECT TO_JSON(COLLECT_LIST(username)) FROM users;

-- STRUCT 构造
SELECT STRUCT(username AS name, age);

-- MAP 构造
SELECT MAP('key1', 'value1', 'key2', 'value2');

-- ARRAY 构造
SELECT ARRAY('a', 'b', 'c');

-- ============================================================
-- Schema Evolution（JSON 字段变化）
-- ============================================================

-- 启用 Schema 合并后，新字段自动添加
ALTER TABLE events SET TBLPROPERTIES ('delta.autoOptimize.optimizeWrite' = 'true');

-- 读取包含不同 Schema 的 JSON 文件
SELECT * FROM JSON.`s3://my-bucket/data/*.json`;

-- ============================================================
-- 查询 Delta Lake 中的嵌套数据
-- ============================================================

-- 嵌套 STRUCT 展平
SELECT
    id,
    address.city,
    address.street
FROM users
WHERE address.city = 'Shanghai';

-- 数组 + 条件
SELECT name, tag
FROM users
LATERAL VIEW EXPLODE(tags) t AS tag
WHERE tag LIKE 'v%';

-- 注意：推荐使用原生 STRUCT/ARRAY/MAP 类型（性能优于 JSON 字符串）
-- 注意：GET_JSON_OBJECT 和 : 语法用于 JSON 字符串查询
-- 注意：FROM_JSON / TO_JSON 在 STRUCT 和 JSON 字符串之间转换
-- 注意：VARIANT 类型（2024+）提供原生半结构化数据支持
-- 注意：Delta Lake 的 Schema Evolution 支持 JSON 字段变化
-- 注意：Parquet 列存储对 STRUCT 类型有高效的列裁剪
