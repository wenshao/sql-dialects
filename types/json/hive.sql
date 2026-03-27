-- Hive: JSON 类型
--
-- 参考资料:
--   [1] Apache Hive - get_json_object
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-get_json_object
--   [2] Apache Hive - JSON SerDe
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-JSON

-- 没有原生 JSON 类型
-- 使用 STRING 存储 JSON，配合 JSON 函数和 SerDe 操作
-- 复合类型：MAP / ARRAY / STRUCT / UNIONTYPE

CREATE TABLE events (
    id   BIGINT,
    data STRING                            -- 存储 JSON 字符串
);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25}');

-- 读取 JSON 字段
SELECT GET_JSON_OBJECT(data, '$.name') FROM events;      -- 返回 STRING
SELECT GET_JSON_OBJECT(data, '$.age') FROM events;       -- 返回 STRING
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events;   -- 数组元素
SELECT GET_JSON_OBJECT(data, '$.addr.city') FROM events;  -- 嵌套键

-- 一次提取多个字段
SELECT JSON_TUPLE(data, 'name', 'age') AS (name, age) FROM events;

-- 查询条件
SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';

-- JSON SerDe（用表结构直接映射 JSON）
CREATE TABLE json_events (
    name   STRING,
    age    INT,
    tags   ARRAY<STRING>
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe';
-- 自动将 JSON 字段映射为列

-- 复合类型（推荐替代 JSON）
-- ARRAY<T>: 数组
-- MAP<K, V>: 键值对
-- STRUCT<f1:T1, f2:T2>: 结构体
-- UNIONTYPE<T1, T2>: 联合类型（少用）

CREATE TABLE users (
    name     STRING,
    address  STRUCT<street:STRING, city:STRING, zip:STRING>,
    tags     ARRAY<STRING>,
    props    MAP<STRING, STRING>
);

-- 访问复合类型
SELECT address.city FROM users;
SELECT tags[0] FROM users;
SELECT props['key1'] FROM users;
SELECT SIZE(tags) FROM users;
SELECT SIZE(props) FROM users;

-- 数组操作
SELECT ARRAY(1, 2, 3);
SELECT ARRAY_CONTAINS(tags, 'vip') FROM users;
SELECT SORT_ARRAY(tags) FROM users;       -- 排序
SELECT EXPLODE(tags) AS tag FROM users;   -- 展开为多行
SELECT POSEXPLODE(tags) AS (pos, tag) FROM users;  -- 带位置展开

-- MAP 操作
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT MAP_KEYS(props) FROM users;
SELECT MAP_VALUES(props) FROM users;

-- STRUCT 操作
SELECT NAMED_STRUCT('name', 'alice', 'age', 25);
SELECT STRUCT('alice', 25);

-- LATERAL VIEW（展开复合类型与原表关联）
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- 注意：没有原生 JSON 类型，用 STRING 存储
-- 注意：推荐使用 MAP/ARRAY/STRUCT + SerDe 替代纯 JSON 字符串
-- 注意：GET_JSON_OBJECT 每次调用都要解析，性能差
-- 注意：JSON SerDe 可以直接将 JSON 文件映射为 Hive 表
