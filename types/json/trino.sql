-- Trino: JSON 类型
--
-- 参考资料:
--   [1] Trino - JSON Data Type
--       https://trino.io/docs/current/language/types.html
--   [2] Trino - JSON Functions
--       https://trino.io/docs/current/functions/json.html

-- JSON: 原生 JSON 类型（存储 JSON 文本）
-- 底层使用 VARCHAR 存储，但提供 JSON 语义

CREATE TABLE events (
    id   BIGINT,
    data JSON
);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, JSON '{"name": "alice", "age": 25, "tags": ["vip"]}');

-- 读取 JSON 字段（使用函数）
SELECT JSON_EXTRACT(data, '$.name') FROM events;           -- 返回 JSON
SELECT JSON_EXTRACT_SCALAR(data, '$.name') FROM events;    -- 返回 VARCHAR
SELECT JSON_EXTRACT(data, '$.tags[0]') FROM events;        -- 数组元素
SELECT JSON_EXTRACT_SCALAR(data, '$.address.city') FROM events;  -- 嵌套

-- SQL 标准 JSON 函数（推荐）
SELECT JSON_VALUE(data, 'lax $.name') FROM events;         -- 返回标量
SELECT JSON_QUERY(data, 'lax $.tags') FROM events;         -- 返回 JSON
SELECT JSON_EXISTS(data, 'lax $.name') FROM events;        -- 是否存在

-- 查询条件
SELECT * FROM events WHERE JSON_EXTRACT_SCALAR(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(JSON_EXTRACT_SCALAR(data, '$.age') AS INTEGER) > 20;

-- 类型转换
SELECT CAST(data AS VARCHAR) FROM events;  -- JSON -> VARCHAR
SELECT CAST('{"a": 1}' AS JSON);           -- VARCHAR -> JSON
SELECT JSON_PARSE('{"a": 1}');             -- 解析 JSON
SELECT JSON_FORMAT(JSON '{"a": 1}');       -- 格式化为 VARCHAR

-- JSON 构造
SELECT JSON_OBJECT(KEY 'name' VALUE 'alice', KEY 'age' VALUE 25);
SELECT JSON_ARRAY(1, 2, 3);
SELECT CAST(MAP(ARRAY['a', 'b'], ARRAY[1, 2]) AS JSON);

-- JSON 数组操作
SELECT JSON_ARRAY_LENGTH(JSON '[1, 2, 3]');                -- 3
SELECT JSON_ARRAY_GET(JSON '[1, 2, 3]', 0);                -- 1
SELECT JSON_ARRAY_CONTAINS(JSON '[1, 2, 3]', 2);           -- true

-- JSON 大小
SELECT JSON_SIZE(data, '$.tags') FROM events;  -- 元素数量

-- ROW 类型（Trino 的结构体，替代 STRUCT）
CREATE TABLE users (
    name    VARCHAR,
    address ROW(street VARCHAR, city VARCHAR, zip VARCHAR)
);
SELECT address.city FROM users;

-- ARRAY 类型
CREATE TABLE t (tags ARRAY(VARCHAR));
SELECT element_at(tags, 1) FROM t;        -- 1-based 索引
SELECT cardinality(tags) FROM t;          -- 长度
SELECT contains(tags, 'vip') FROM t;      -- 包含检查
SELECT t.tag FROM t CROSS JOIN UNNEST(tags) AS t(tag);  -- 展开

-- MAP 类型
CREATE TABLE configs (props MAP(VARCHAR, VARCHAR));
SELECT element_at(props, 'key1') FROM configs;
SELECT map_keys(props) FROM configs;
SELECT map_values(props) FROM configs;

-- 注意：JSON 底层用 VARCHAR 存储（无 JSONB 二进制格式）
-- 注意：推荐 ROW/ARRAY/MAP 用于结构化数据（性能更好）
-- 注意：JSON 函数支持 lax/strict 模式（SQL 标准）
-- 注意：底层存储效率取决于 Connector（如 Hive、Iceberg）
