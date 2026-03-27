-- Apache Impala: JSON 类型
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 没有原生 JSON 类型
-- JSON 数据以 STRING 存储，通过函数解析

-- ============================================================
-- STRING 存储 JSON
-- ============================================================

CREATE TABLE events (
    id   BIGINT,
    data STRING                            -- JSON 以字符串存储
)
STORED AS PARQUET;

-- 插入 JSON
INSERT INTO events VALUES
    (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}'),
    (2, '{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');

-- ============================================================
-- GET_JSON_OBJECT（提取 JSON 值）
-- ============================================================

-- 使用 JSONPath 语法
SELECT GET_JSON_OBJECT(data, '$.name') FROM events;           -- alice
SELECT GET_JSON_OBJECT(data, '$.age') FROM events;            -- 25
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events;        -- vip
SELECT GET_JSON_OBJECT(data, '$.address.city') FROM events;   -- Beijing

-- 带类型转换
SELECT CAST(GET_JSON_OBJECT(data, '$.age') AS INT) FROM events;

-- ============================================================
-- JSON 查询
-- ============================================================

SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(GET_JSON_OBJECT(data, '$.age') AS INT) > 25;
SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.address') IS NOT NULL;

-- ============================================================
-- 复杂类型替代方案
-- ============================================================

-- Impala 支持 STRUCT / MAP / ARRAY 复杂类型
-- 比 JSON 字符串解析更高效

CREATE TABLE events_structured (
    id         BIGINT,
    name       STRING,
    age        INT,
    tags       ARRAY<STRING>,
    address    STRUCT<city:STRING, zip:STRING>,
    metadata   MAP<STRING, STRING>
)
STORED AS PARQUET;

-- 访问复杂类型
SELECT tags[0] FROM events_structured;
SELECT address.city FROM events_structured;
SELECT metadata['key1'] FROM events_structured;

-- 展开数组
SELECT id, tag
FROM events_structured, events_structured.tags AS tag;

-- 展开 MAP
SELECT id, key, value
FROM events_structured, events_structured.metadata;

-- ============================================================
-- Parquet/ORC 中的 JSON
-- ============================================================

-- Parquet 文件中 JSON 通常以 STRING 列存储
-- 或者使用嵌套类型（STRUCT/ARRAY/MAP）

-- 从 JSON 文件创建外部表
-- CREATE EXTERNAL TABLE json_events (
--     name STRING,
--     age INT
-- )
-- STORED AS TEXTFILE
-- LOCATION '/data/json_events/';

-- 注意：Impala 没有原生 JSON 类型
-- 注意：使用 GET_JSON_OBJECT 解析 JSON 字符串
-- 注意：复杂类型（STRUCT/ARRAY/MAP）比 JSON 字符串更高效
-- 注意：GET_JSON_OBJECT 返回 STRING 类型，需要 CAST 转换
