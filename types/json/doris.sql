-- Apache Doris: JSON 类型（2.0+）
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- JSON 列
CREATE TABLE events (
    id   BIGINT NOT NULL,
    data JSON
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 插入 JSON
INSERT INTO events (id, data) VALUES
    (1, '{"name": "alice", "age": 25, "tags": ["vip", "new"]}'),
    (2, '{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');

-- 构造 JSON
INSERT INTO events (id, data) VALUES
    (3, JSON_OBJECT('name', 'charlie', 'age', 35)),
    (4, JSON_ARRAY(1, 2, 3));

-- ============================================================
-- JSON 路径访问
-- ============================================================

-- json_extract（返回 JSON 值）
SELECT json_extract(data, '$.name') FROM events;          -- "alice"
SELECT json_extract(data, '$.age') FROM events;           -- 25
SELECT json_extract(data, '$.tags[0]') FROM events;       -- "vip"
SELECT json_extract(data, '$.address.city') FROM events;  -- "Beijing"

-- json_extract_string（返回字符串）
SELECT json_extract_string(data, '$.name') FROM events;   -- alice（无引号）

-- 简写箭头运算符（2.1+）
SELECT data->'name' FROM events;                          -- "alice"
SELECT data->>'name' FROM events;                         -- alice

-- 嵌套访问
SELECT data->'address'->'city' FROM events;
SELECT data->>'address'->>'city' FROM events;

-- ============================================================
-- JSON 查询
-- ============================================================

SELECT * FROM events WHERE json_extract_string(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(json_extract(data, '$.age') AS INT) > 25;
SELECT * FROM events WHERE json_contains(data, '"vip"', '$.tags');
SELECT * FROM events WHERE json_exists_path(data, '$.address');

-- ============================================================
-- JSON 函数
-- ============================================================

SELECT json_type(data, '$.name') FROM events;             -- STRING
SELECT json_length(data, '$.tags') FROM events;           -- 2
SELECT json_keys(data) FROM events;                       -- ["name","age","tags"]

-- JSON 修改
SELECT json_insert(data, '$.email', 'a@e.com') FROM events;
SELECT json_replace(data, '$.age', 26) FROM events;
SELECT json_set(data, '$.age', 26) FROM events;

-- JSONB 二进制格式（2.1+，存储和查询更高效）
CREATE TABLE events_b (
    id   BIGINT NOT NULL,
    data JSONB
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 注意：JSON 类型在 Doris 2.0+ 可用
-- 注意：2.1+ 支持箭头运算符 -> 和 ->>
-- 注意：JSONB 是二进制存储格式，查询更高效
-- 注意：JSON 列不能作为 Key 列、分区列或分桶列
-- 注意：json_extract 返回 JSON 类型，json_extract_string 返回 VARCHAR
