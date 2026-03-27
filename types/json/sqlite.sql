-- SQLite: JSON 支持（3.9.0+ 可加载扩展，3.38.0+ 默认内置）
--
-- 参考资料:
--   [1] SQLite Documentation - JSON Functions
--       https://www.sqlite.org/json1.html
--   [2] SQLite Documentation - JSON (Built-in, 3.38.0+)
--       https://www.sqlite.org/json1.html#compiling-in-json-support

-- 没有专门的 JSON 类型，JSON 存储为 TEXT
CREATE TABLE events (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    data TEXT                          -- 存储 JSON 文本
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (json_object('name', 'bob', 'age', 30));
INSERT INTO events (data) VALUES (json_array(1, 2, 3));

-- 读取 JSON 字段
SELECT json_extract(data, '$.name') FROM events;           -- alice
SELECT data->>'$.name' FROM events;                        -- alice（3.38.0+）
SELECT data->'$.name' FROM events;                         -- "alice"（3.38.0+）

-- 嵌套访问
SELECT json_extract(data, '$.tags[0]') FROM events;        -- vip
SELECT data->>'$.tags[0]' FROM events;

-- 查询条件
SELECT * FROM events WHERE json_extract(data, '$.name') = 'alice';

-- 修改 JSON
SELECT json_set(data, '$.age', 26) FROM events;            -- 设置
SELECT json_insert(data, '$.email', 'a@e.com') FROM events; -- 插入
SELECT json_replace(data, '$.age', 26) FROM events;        -- 替换
SELECT json_remove(data, '$.tags') FROM events;             -- 删除

-- JSON 函数
SELECT json_type(data) FROM events;                         -- object
SELECT json_valid('{"a":1}');                               -- 1
SELECT json_array_length(json_extract(data, '$.tags')) FROM events; -- 2

-- 展开 JSON 数组为行
SELECT value FROM events, json_each(json_extract(data, '$.tags'));

-- 展开 JSON 对象为键值对
SELECT key, value FROM events, json_each(data);

-- JSON 聚合（3.33.0+）
SELECT json_group_array(username) FROM users;
SELECT json_group_object(username, age) FROM users;

-- 3.45.0+: JSONB 二进制格式（内部优化，减少解析开销）
SELECT jsonb('{"name": "alice"}');
