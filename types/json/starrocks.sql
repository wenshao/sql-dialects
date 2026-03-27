-- StarRocks: JSON 类型
--
-- 参考资料:
--   [1] StarRocks - JSON Data Type
--       https://docs.starrocks.io/docs/sql-reference/data-types/semi_structured/JSON/
--   [2] StarRocks - JSON Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/json-functions/

-- JSON: 半结构化数据类型（2.2+）
-- 之前使用 VARCHAR 存储 JSON

CREATE TABLE events (
    id   BIGINT,
    data JSON                              -- JSON 类型（2.2+）
)
DISTRIBUTED BY HASH(id);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events (id, data) VALUES (2, JSON_OBJECT('name', 'bob', 'age', 30));
INSERT INTO events (id, data) VALUES (3, PARSE_JSON('{"name": "charlie"}'));

-- 读取 JSON 字段
SELECT data->'name' FROM events;           -- 返回 JSON
SELECT data->>'name' FROM events;          -- 返回 STRING（3.0+）
SELECT JSON_QUERY(data, '$.name') FROM events;      -- 返回 JSON
SELECT JSON_VALUE(data, '$.name') FROM events;      -- 返回 STRING（标量）

-- 数组访问
SELECT data->'tags'->'0' FROM events;
SELECT JSON_QUERY(data, '$.tags[0]') FROM events;
SELECT JSON_LENGTH(data->'tags') FROM events;

-- 查询条件
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(data->'age' AS INT) > 20;

-- JSON 构造
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_ARRAY(1, 2, 3);
SELECT PARSE_JSON('{"key": "value"}');
SELECT TO_JSON(MAP{'name': 'alice', 'age': '25'});

-- JSON 类型判断
SELECT JSON_EXISTS(data, '$.name') FROM events;
SELECT GET_JSON_STRING(data, '$.name') FROM events;
SELECT GET_JSON_INT(data, '$.age') FROM events;
SELECT GET_JSON_DOUBLE(data, '$.score') FROM events;

-- ARRAY 类型（原生）
CREATE TABLE users (
    name  VARCHAR(100),
    tags  ARRAY<VARCHAR(100)>              -- 原生数组类型（2.1+）
)
DISTRIBUTED BY HASH(name);
SELECT tags[1] FROM users;                -- 1-based 索引
SELECT ARRAY_LENGTH(tags) FROM users;

-- MAP 类型（3.1+）
CREATE TABLE configs (
    id    BIGINT,
    props MAP<VARCHAR(100), VARCHAR(100)>   -- MAP 类型（3.1+）
)
DISTRIBUTED BY HASH(id);

-- STRUCT 类型（3.1+）
CREATE TABLE records (
    id      BIGINT,
    address STRUCT<street VARCHAR(200), city VARCHAR(100)>
)
DISTRIBUTED BY HASH(id);
SELECT address.city FROM records;

-- 注意：JSON 类型在 2.2+ 引入
-- 注意：-> 返回 JSON，->> 返回 STRING（3.0+）
-- 注意：JSON 列不能作为排序键或分桶键
-- 注意：ARRAY/MAP/STRUCT 原生类型性能优于 JSON
