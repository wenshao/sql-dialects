-- SQL Server: JSON 支持（2016+）
--
-- 参考资料:
--   [1] SQL Server - JSON Data
--       https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server
--   [2] SQL Server T-SQL - JSON Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/json-functions-transact-sql

-- 没有原生 JSON 类型，存储在 NVARCHAR 中
CREATE TABLE events (
    id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    data NVARCHAR(MAX)
);
-- 可以用 CHECK 约束验证
ALTER TABLE events ADD CONSTRAINT chk_json CHECK (ISJSON(data) = 1);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- 读取 JSON 字段
SELECT JSON_VALUE(data, '$.name') FROM events;             -- alice（返回标量）
SELECT JSON_QUERY(data, '$.tags') FROM events;             -- ["vip", "new"]（返回对象/数组）

-- 嵌套访问
SELECT JSON_VALUE(data, '$.tags[0]') FROM events;          -- vip

-- 查询条件
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';

-- 修改 JSON
SELECT JSON_MODIFY(data, '$.age', 26) FROM events;                -- 修改值
SELECT JSON_MODIFY(data, '$.email', 'a@e.com') FROM events;       -- 添加键
SELECT JSON_MODIFY(data, '$.tags', NULL) FROM events;              -- 删除键
SELECT JSON_MODIFY(data, 'append $.tags', 'hot') FROM events;     -- 数组追加

-- OPENJSON（展开 JSON 为行，类似 JSON_TABLE）
SELECT * FROM events
CROSS APPLY OPENJSON(data)
WITH (
    name NVARCHAR(64) '$.name',
    age  INT          '$.age'
);

-- 展开 JSON 数组
SELECT value FROM events
CROSS APPLY OPENJSON(JSON_QUERY(data, '$.tags'));

-- FOR JSON（将查询结果转为 JSON）
SELECT username, email FROM users FOR JSON PATH;
-- [{"username":"alice","email":"alice@example.com"}, ...]

SELECT username, email FROM users FOR JSON AUTO;           -- 自动嵌套
SELECT username FROM users FOR JSON PATH, ROOT('users');   -- 添加根节点

-- ISJSON
SELECT ISJSON('{"a":1}');                                  -- 1

-- JSON 索引（计算列 + 索引）
ALTER TABLE events ADD name AS JSON_VALUE(data, '$.name');
CREATE INDEX idx_name ON events (name);

-- 2022+: JSON_OBJECT / JSON_ARRAY
SELECT JSON_OBJECT('name': username, 'age': age) FROM users;
SELECT JSON_ARRAY(username, email) FROM users;
