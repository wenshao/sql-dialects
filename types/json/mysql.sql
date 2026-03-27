-- MySQL: JSON 类型（5.7.8+）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - JSON Data Type
--       https://dev.mysql.com/doc/refman/8.0/en/json.html
--   [2] MySQL 8.0 Reference Manual - JSON Functions
--       https://dev.mysql.com/doc/refman/8.0/en/json-functions.html
--   [3] MySQL 8.0 Reference Manual - JSON Path Syntax
--       https://dev.mysql.com/doc/refman/8.0/en/json-path-syntax.html

-- JSON 列
CREATE TABLE events (
    id   BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    data JSON
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (JSON_OBJECT('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (JSON_ARRAY(1, 2, 3));

-- 读取 JSON 字段
SELECT data->'$.name' FROM events;                   -- 返回 JSON 值: "alice"
SELECT data->>'$.name' FROM events;                  -- 返回文本值: alice（5.7.13+）
SELECT JSON_EXTRACT(data, '$.name') FROM events;     -- 同 ->
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events; -- 同 ->>

-- 嵌套访问
SELECT data->'$.tags[0]' FROM events;                -- "vip"
SELECT data->>'$.address.city' FROM events;

-- 查询条件
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');
SELECT * FROM events WHERE JSON_CONTAINS_PATH(data, 'one', '$.name', '$.email');

-- 修改 JSON
SELECT JSON_SET(data, '$.age', 26) FROM events;       -- 设置（不存在则插入，已存在则更新）
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events; -- 插入（已存在则不变）
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;   -- 替换（不存在则不变）
SELECT JSON_REMOVE(data, '$.tags') FROM events;        -- 删除键

-- JSON 函数
SELECT JSON_TYPE(data->'$.name') FROM events;          -- STRING
SELECT JSON_VALID('{"a":1}');                          -- 1
SELECT JSON_KEYS(data) FROM events;                    -- ["name", "age", "tags"]
SELECT JSON_LENGTH(data->'$.tags') FROM events;        -- 2

-- JSON 聚合（5.7.22+）
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- JSON 表（8.0+，将 JSON 展开为行）
SELECT * FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age INT PATH '$.age'
)) AS jt;

-- 8.0.17+: 多值索引（索引 JSON 数组中的值）
CREATE INDEX idx_tags ON events ((CAST(data->'$.tags' AS CHAR(64) ARRAY)));
