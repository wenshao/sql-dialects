-- MaxCompute (ODPS): JSON 类型
--
-- 参考资料:
--   [1] MaxCompute - JSON Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/json-functions
--   [2] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1

-- MaxCompute 支持原生 JSON 类型（较新版本）
-- 也可以使用 STRING 存储 JSON，配合 JSON 函数操作
-- 复合类型：MAP / ARRAY / STRUCT（2.0+）

CREATE TABLE events (
    id   BIGINT,
    data STRING                            -- 用 STRING 存储 JSON 字符串（兼容方式）
);

-- 使用原生 JSON 类型（推荐）
CREATE TABLE events_v2 (
    id   BIGINT,
    data JSON                              -- 原生 JSON 类型
);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25}');

-- 读取 JSON 字段
SELECT GET_JSON_OBJECT(data, '$.name') FROM events;      -- 返回 STRING
SELECT GET_JSON_OBJECT(data, '$.age') FROM events;       -- 返回 STRING
SELECT GET_JSON_OBJECT(data, '$.tags[0]') FROM events;   -- 数组元素

-- JSON 路径语法（jQuery 风格）
-- $.key: 顶层键
-- $.key1.key2: 嵌套键
-- $.array[0]: 数组元素

-- 查询条件
SELECT * FROM events WHERE GET_JSON_OBJECT(data, '$.name') = 'alice';

-- 复合类型（2.0+，替代 JSON 的推荐方案）
-- MAP<K, V>: 键值对
-- ARRAY<T>: 数组
-- STRUCT<f1:T1, f2:T2>: 结构体
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

-- MAP 构造
SELECT MAP('k1', 'v1', 'k2', 'v2');
SELECT MAP_KEYS(props) FROM users;
SELECT MAP_VALUES(props) FROM users;
SELECT SIZE(props) FROM users;

-- ARRAY 构造
SELECT ARRAY('a', 'b', 'c');
SELECT SIZE(tags) FROM users;
SELECT ARRAY_CONTAINS(tags, 'vip') FROM users;
SELECT EXPLODE(tags) AS tag FROM users;   -- 展开数组

-- STRUCT 构造
SELECT NAMED_STRUCT('name', 'alice', 'age', 25);
SELECT STRUCT('alice', 25);

-- JSON 函数（有限支持）
SELECT JSON_TUPLE(data, 'name', 'age') FROM events;  -- 一次提取多个键

-- 注意：较新版本支持原生 JSON 类型，旧版本用 STRING 存储
-- 注意：结构化数据推荐使用 MAP/ARRAY/STRUCT（性能更好）
-- 注意：GET_JSON_OBJECT 性能不如原生复合类型
-- 注意：2.0 需开启 set odps.sql.type.system.odps2 = true;
