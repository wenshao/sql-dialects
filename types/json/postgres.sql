-- PostgreSQL: JSON 类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - JSON Types
--       https://www.postgresql.org/docs/current/datatype-json.html
--   [2] PostgreSQL Documentation - JSON Functions
--       https://www.postgresql.org/docs/current/functions-json.html

-- 两种 JSON 类型:
-- JSON:  存储原始文本，每次访问都要解析（9.2+）
-- JSONB: 存储二进制格式，支持索引，更快（9.4+，推荐）

CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB                         -- 推荐用 JSONB
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- 读取 JSON 字段
SELECT data->'name' FROM events;               -- 返回 JSON: "alice"
SELECT data->>'name' FROM events;              -- 返回文本: alice
SELECT data->'tags'->0 FROM events;            -- 第一个元素: "vip"
SELECT data#>'{tags,0}' FROM events;           -- 路径访问: "vip"
SELECT data#>>'{tags,0}' FROM events;          -- 路径访问返回文本: vip

-- 14+: 下标访问
SELECT data['name'] FROM events;               -- "alice"
SELECT data['tags'][0] FROM events;            -- "vip"

-- 查询条件
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE data @> '{"name": "alice"}';  -- 包含（JSONB 专用）
SELECT * FROM events WHERE data ? 'name';                -- 键存在（JSONB 专用）
SELECT * FROM events WHERE data ?& ARRAY['name', 'age']; -- 所有键存在
SELECT * FROM events WHERE data ?| ARRAY['name', 'email']; -- 任一键存在

-- JSONB 修改（9.5+）
SELECT data || '{"email": "a@e.com"}' FROM events;       -- 合并
SELECT data - 'tags' FROM events;                          -- 删除键
SELECT data #- '{tags,0}' FROM events;                     -- 删除路径
SELECT jsonb_set(data, '{age}', '26') FROM events;        -- 设置值

-- JSONB 索引
CREATE INDEX idx_data ON events USING gin (data);          -- 支持 @> ? ?& ?|
CREATE INDEX idx_data_path ON events USING gin (data jsonb_path_ops); -- 只支持 @>，更小

-- JSON Path（12+）
SELECT jsonb_path_query(data, '$.tags[*]') FROM events;
SELECT * FROM events WHERE jsonb_path_exists(data, '$.tags[*] ? (@ == "vip")');

-- JSON 聚合
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(username, age) FROM users;

-- JSON 展开
SELECT e.key, e.value FROM events, jsonb_each(data) e;      -- 键值对
SELECT t.value FROM events, jsonb_array_elements(data->'tags') t; -- 数组元素

-- 17+: JSON_TABLE（将 JSON 展开为关系表，SQL 标准语法）
