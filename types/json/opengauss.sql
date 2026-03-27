-- openGauss/GaussDB: JSON 类型
-- PostgreSQL compatible JSON/JSONB support.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- JSON 和 JSONB 类型
-- JSON: 存储原始文本
-- JSONB: 二进制格式，支持索引（推荐）
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
SELECT data#>'{tags,0}' FROM events;           -- 路径: "vip"
SELECT data#>>'{tags,0}' FROM events;          -- 路径文本: vip

-- 查询条件
SELECT * FROM events WHERE data->>'name' = 'alice';
SELECT * FROM events WHERE data @> '{"name": "alice"}';  -- 包含
SELECT * FROM events WHERE data ? 'name';                -- 键存在
SELECT * FROM events WHERE data ?& ARRAY['name', 'age']; -- 所有键
SELECT * FROM events WHERE data ?| ARRAY['name', 'email']; -- 任一键

-- JSONB 修改
SELECT data || '{"email": "a@e.com"}' FROM events;       -- 合并
SELECT data - 'tags' FROM events;                          -- 删除键
SELECT data #- '{tags,0}' FROM events;                     -- 删除路径
SELECT jsonb_set(data, '{age}', '26') FROM events;        -- 设置值

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
-- JSON/JSONB 类型与 PostgreSQL 兼容
-- 推荐使用 JSONB 类型（支持索引和更多操作符）
-- 支持 GIN 索引加速 JSONB 查询
