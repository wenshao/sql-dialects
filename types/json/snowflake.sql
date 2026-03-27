-- Snowflake: JSON 类型
--
-- 参考资料:
--   [1] Snowflake SQL Reference - VARIANT Data Type
--       https://docs.snowflake.com/en/sql-reference/data-types-semistructured
--   [2] Snowflake SQL Reference - Semi-Structured Functions
--       https://docs.snowflake.com/en/sql-reference/functions-semistructured

-- VARIANT: 半结构化数据类型（存储 JSON、Avro、ORC、Parquet 等）
-- OBJECT: 键值对集合（类似 JSON 对象）
-- ARRAY: 有序值集合（类似 JSON 数组）
-- 注意：没有单独的 JSON 类型，使用 VARIANT

CREATE TABLE events (
    id   INTEGER,
    data VARIANT                           -- 存储 JSON/半结构化数据
);

-- 插入 JSON
INSERT INTO events (id, data) VALUES (1, PARSE_JSON('{"name": "alice", "age": 25, "tags": ["vip"]}'));
INSERT INTO events (id, data) VALUES (2, OBJECT_CONSTRUCT('name', 'bob', 'age', 30));

-- 读取 JSON 字段
SELECT data:name FROM events;              -- 冒号访问（返回 VARIANT）
SELECT data:name::STRING FROM events;      -- 转为 STRING
SELECT data:tags[0]::STRING FROM events;   -- 数组下标
SELECT data:address.city FROM events;      -- 嵌套访问
SELECT data['name'] FROM events;           -- 括号访问

-- 点号 vs 冒号:
-- 冒号(:) 用于 VARIANT 第一层访问
-- 点号(.) 用于嵌套层级
-- 括号([]) 用于数组下标或动态键名

-- 查询条件
SELECT * FROM events WHERE data:name::STRING = 'alice';
SELECT * FROM events WHERE data:age::INT > 20;

-- 类型转换
SELECT data:name::STRING FROM events;      -- VARIANT -> STRING
SELECT data:age::INTEGER FROM events;      -- VARIANT -> INTEGER
SELECT TRY_CAST(data:age AS INTEGER) FROM events;  -- 安全转换

-- JSON 类型判断
SELECT TYPEOF(data:name) FROM events;      -- 'VARCHAR'
SELECT IS_NULL_VALUE(data:email) FROM events;  -- JSON null 判断
SELECT IS_OBJECT(data) FROM events;
SELECT IS_ARRAY(data:tags) FROM events;

-- VARIANT 构造
SELECT PARSE_JSON('{"name": "alice"}');
SELECT OBJECT_CONSTRUCT('name', 'alice', 'age', 25);
SELECT OBJECT_CONSTRUCT_KEEP_NULL('a', 1, 'b', NULL);
SELECT ARRAY_CONSTRUCT(1, 2, 3);
SELECT TO_VARIANT('hello');

-- VARIANT 修改
SELECT OBJECT_INSERT(data, 'email', 'a@e.com') FROM events;    -- 添加键
SELECT OBJECT_DELETE(data, 'tags') FROM events;                  -- 删除键
SELECT ARRAY_APPEND(data:tags, 'new_tag') FROM events;          -- 数组追加
SELECT ARRAY_PREPEND(data:tags, 'first') FROM events;           -- 数组前插

-- JSON 展开（FLATTEN）
SELECT f.value::STRING AS tag
FROM events, LATERAL FLATTEN(input => data:tags) f;

SELECT f.key, f.value
FROM events, LATERAL FLATTEN(input => data) f;

-- 递归展开
SELECT f.path, f.key, f.value
FROM events, LATERAL FLATTEN(input => data, recursive => true) f;

-- OBJECT/ARRAY 聚合
SELECT OBJECT_AGG(key, value) FROM t;
SELECT ARRAY_AGG(value) FROM t;

-- 注意：VARIANT 是 Snowflake 的核心特性，非常强大
-- 注意：VARIANT 最大 16MB
-- 注意：VARIANT 列会自动推断子列用于优化查询
-- 注意：与 PostgreSQL 的 JSONB 类似但语法不同
