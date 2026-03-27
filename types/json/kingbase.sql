-- KingbaseES (人大金仓): JSON 类型
-- PostgreSQL compatible JSON/JSONB support.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- JSON 和 JSONB 类型
CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

-- 读取 JSON 字段
SELECT data->'name' FROM events;               -- JSON: "alice"
SELECT data->>'name' FROM events;              -- 文本: alice
SELECT data->'tags'->0 FROM events;            -- "vip"
SELECT data#>'{tags,0}' FROM events;           -- 路径
SELECT data#>>'{tags,0}' FROM events;          -- 路径文本

-- 查询条件
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE data @> '{"name": "alice"}';
SELECT * FROM events WHERE data ? 'name';
SELECT * FROM events WHERE data ?& ARRAY['name', 'age'];
SELECT * FROM events WHERE data ?| ARRAY['name', 'email'];

-- JSONB 修改
SELECT data || '{"email": "a@e.com"}' FROM events;
SELECT data - 'tags' FROM events;
SELECT data #- '{tags,0}' FROM events;
SELECT jsonb_set(data, '{age}', '26') FROM events;

-- JSONB 索引
CREATE INDEX idx_data ON events USING gin (data);
CREATE INDEX idx_data_path ON events USING gin (data jsonb_path_ops);

-- JSON 聚合
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_object_agg(username, age) FROM users;

-- JSON 展开
SELECT * FROM jsonb_each(data) FROM events;
SELECT * FROM jsonb_array_elements(data->'tags') FROM events;

-- 注意事项：
-- JSON/JSONB 类型与 PostgreSQL 完全兼容
-- 推荐使用 JSONB（支持索引和更多操作符）
-- 支持 GIN 索引加速查询
