-- BigQuery: JSON 类型
--
-- 参考资料:
--   [1] BigQuery SQL Reference - JSON Data Type
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#json_type
--   [2] BigQuery SQL Reference - JSON Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions

-- JSON: 原生 JSON 类型（2022+）
-- 之前需要用 STRING 存储 JSON 并用 JSON 函数解析

CREATE TABLE events (
    id   INT64,
    data JSON                              -- 原生 JSON 类型
);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, JSON '{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events (id, data) VALUES (2, JSON_OBJECT('name', 'bob', 'age', 30));

-- 读取 JSON 字段
SELECT data.name FROM events;              -- 点号访问（返回 JSON）
SELECT data.tags[0] FROM events;           -- 数组下标访问
SELECT JSON_VALUE(data, '$.name') FROM events;          -- 返回 STRING 标量值
SELECT JSON_QUERY(data, '$.tags') FROM events;          -- 返回 JSON 数组/对象

-- STRING_VALUE vs JSON_QUERY:
-- JSON_VALUE: 提取标量值，返回 STRING
-- JSON_QUERY: 提取数组/对象，返回 JSON

-- 查询条件
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';
SELECT * FROM events WHERE BOOL(data.age > 20);

-- 类型转换
SELECT BOOL(JSON 'true');                  -- BOOL
SELECT INT64(JSON '123');                  -- INT64
SELECT FLOAT64(JSON '3.14');               -- FLOAT64
SELECT STRING(JSON '"hello"');             -- STRING
SELECT JSON_VALUE(data, '$.age' RETURNING INT64) FROM events;  -- 直接转换

-- JSON 构造
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_ARRAY(1, 2, 3);
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));    -- STRUCT 转 JSON

-- JSON 修改（LAX 模式）
SELECT JSON_SET('{"a": 1}', '$.b', 2);                -- 添加/修改
SELECT JSON_STRIP_NULLS(JSON '{"a": 1, "b": null}');  -- 移除 NULL
SELECT JSON_REMOVE(JSON '{"a": 1, "b": 2}', '$.b');   -- 删除键

-- JSON 展开
SELECT * FROM UNNEST(JSON_QUERY_ARRAY(data, '$.tags')) AS tag FROM events;
SELECT * FROM UNNEST(JSON_KEYS(data)) AS key_name FROM events;

-- STRUCT 和 ARRAY（BigQuery 原生复合类型）
-- BigQuery 推荐使用 STRUCT/ARRAY 而非 JSON 存储结构化数据
CREATE TABLE users (
    name    STRING,
    address STRUCT<street STRING, city STRING, zip STRING>,
    tags    ARRAY<STRING>
);
SELECT address.city FROM users;
SELECT tag FROM users, UNNEST(tags) AS tag;

-- JSON Path
SELECT JSON_VALUE(data, '$.name') FROM events;
SELECT JSON_QUERY(data, '$.tags[0]') FROM events;

-- 注意：JSON 类型是 2022 年引入的，之前用 STRING + JSON 函数
-- 注意：BigQuery 推荐原生 STRUCT/ARRAY 优于 JSON（性能更好）
-- 注意：JSON 列不支持排序和分组
