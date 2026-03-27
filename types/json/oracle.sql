-- Oracle: JSON 支持
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - JSON Data Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html
--   [2] Oracle JSON Developer's Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/adjsn/

-- 12c R1+: JSON 存储在 VARCHAR2/CLOB/BLOB 中
-- 21c+: 原生 JSON 类型

-- 12c: 用 VARCHAR2 或 CLOB 存储
CREATE TABLE events (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data CLOB CONSTRAINT chk_json CHECK (data IS JSON)
);

-- 21c+: 原生 JSON 类型
CREATE TABLE events (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data JSON
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- 读取 JSON 字段（点符号，12c+）
SELECT e.data.name FROM events e;                          -- alice
SELECT e.data.tags[0] FROM events e;                       -- vip

-- JSON_VALUE（返回标量值）
SELECT JSON_VALUE(data, '$.name') FROM events;             -- alice
SELECT JSON_VALUE(data, '$.age' RETURNING NUMBER) FROM events; -- 25

-- JSON_QUERY（返回 JSON 片段）
SELECT JSON_QUERY(data, '$.tags') FROM events;             -- ["vip", "new"]

-- 查询条件
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';
SELECT * FROM events WHERE JSON_EXISTS(data, '$.tags[*]?(@ == "vip")');

-- 12c+: IS JSON 检查
SELECT * FROM events WHERE data IS JSON;
SELECT * FROM events WHERE data IS NOT JSON;

-- JSON_TABLE（将 JSON 展开为关系表，12c+）
SELECT jt.*
FROM events,
JSON_TABLE(data, '$' COLUMNS (
    name VARCHAR2(64) PATH '$.name',
    age  NUMBER       PATH '$.age'
)) jt;

-- JSON 修改
-- 19c+: JSON_MERGEPATCH
SELECT JSON_MERGEPATCH(data, '{"age": 26}') FROM events;

-- 21c+: JSON_TRANSFORM
SELECT JSON_TRANSFORM(data, SET '$.age' = 26, REMOVE '$.tags') FROM events;

-- JSON 聚合（12c R2+）
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username VALUE age) FROM users;

-- JSON 索引
-- 函数索引
CREATE INDEX idx_name ON events (JSON_VALUE(data, '$.name'));
-- 21c+: 多值索引
CREATE MULTIVALUE INDEX idx_tags ON events e (e.data.tags.string());

-- JSON 搜索索引（全文搜索 JSON 内容）
CREATE SEARCH INDEX idx_search ON events (data) FOR JSON;
