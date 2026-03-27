-- DamengDB (达梦): JSON 类型
-- DamengDB supports JSON data with Oracle-compatible functions.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- 达梦没有原生 JSON 列类型，使用 CLOB 或 VARCHAR 存储 JSON
CREATE TABLE events (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    data CLOB
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- JSON 查询函数
-- JSON_VALUE: 提取标量值
SELECT JSON_VALUE(data, '$.name') FROM events;       -- alice
SELECT JSON_VALUE(data, '$.age') FROM events;        -- 25

-- JSON_QUERY: 提取对象或数组
SELECT JSON_QUERY(data, '$.tags') FROM events;       -- ["vip", "new"]

-- 查询条件
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';

-- JSON_EXISTS: 检查路径是否存在
SELECT * FROM events WHERE JSON_EXISTS(data, '$.name');

-- JSON_TABLE: 将 JSON 展开为关系表
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age  INT PATH '$.age'
)) jt;

-- JSON 数组展开
SELECT jt.tag
FROM events e,
JSON_TABLE(e.data, '$.tags[*]' COLUMNS (
    tag VARCHAR(64) PATH '$'
)) jt;

-- 注意事项：
-- 达梦使用 SQL/JSON 标准函数（JSON_VALUE、JSON_QUERY、JSON_TABLE）
-- 没有原生 JSON 列类型，使用 CLOB 存储
-- 不支持 MySQL 风格的 -> 和 ->> 运算符
-- JSON_TABLE 功能强大，可以将 JSON 转为关系数据
