-- TDSQL: JSON 类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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
SELECT data->'$.name' FROM events;
SELECT data->>'$.name' FROM events;
SELECT JSON_EXTRACT(data, '$.name') FROM events;
SELECT JSON_UNQUOTE(JSON_EXTRACT(data, '$.name')) FROM events;

-- 嵌套访问
SELECT data->'$.tags[0]' FROM events;

-- 查询条件
SELECT * FROM events WHERE data->>'$.name' = 'alice';
SELECT * FROM events WHERE JSON_CONTAINS(data, '"vip"', '$.tags');

-- 修改 JSON
SELECT JSON_SET(data, '$.age', 26) FROM events;
SELECT JSON_INSERT(data, '$.email', 'a@e.com') FROM events;
SELECT JSON_REPLACE(data, '$.age', 26) FROM events;
SELECT JSON_REMOVE(data, '$.tags') FROM events;

-- JSON 函数
SELECT JSON_TYPE(data->'$.name') FROM events;
SELECT JSON_VALID('{"a":1}');
SELECT JSON_KEYS(data) FROM events;
SELECT JSON_LENGTH(data->'$.tags') FROM events;

-- JSON 聚合
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

-- 注意事项：
-- JSON 类型与 MySQL 兼容
-- JSON 列不能作为 shardkey
-- JSON 函数在各分片上独立执行
-- 跨分片的 JSON 聚合由代理层合并
