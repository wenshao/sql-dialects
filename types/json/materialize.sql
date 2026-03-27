-- Materialize: JSON 类型

-- Materialize 支持 JSONB 类型（兼容 PostgreSQL）

CREATE TABLE events (
    id      INT,
    payload JSONB
);

-- 插入 JSON
INSERT INTO events VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events VALUES (2, '{"name": "bob", "age": 30}'::JSONB);

-- 读取 JSON 字段
SELECT payload->'name' FROM events;               -- JSONB 值
SELECT payload->>'name' FROM events;              -- TEXT 值
SELECT payload->'nested'->'key' FROM events;      -- 嵌套访问
SELECT payload#>>'{nested,key}' FROM events;      -- 路径访问

-- 查询条件
SELECT * FROM events WHERE payload->>'name' = 'alice';
SELECT * FROM events WHERE payload @> '{"name": "alice"}'::JSONB;
SELECT * FROM events WHERE payload ? 'name';

-- JSON 构造
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_array(1, 2, 3);
SELECT to_jsonb(ROW('alice', 25));

-- JSON 展开
SELECT * FROM jsonb_each('{"a": 1, "b": 2}'::JSONB);
SELECT * FROM jsonb_array_elements('[1,2,3]'::JSONB);
SELECT jsonb_object_keys(payload) FROM events;

-- JSON 聚合
SELECT jsonb_agg(payload->'name') FROM events;
SELECT jsonb_object_agg(id, payload) FROM events;

-- 类型转换
SELECT (payload->>'age')::INT FROM events;

-- ============================================================
-- 物化视图中的 JSON
-- ============================================================

CREATE MATERIALIZED VIEW user_events AS
SELECT id,
    payload->>'name' AS name,
    (payload->>'age')::INT AS age
FROM events;

-- SOURCE 中的 JSON
CREATE SOURCE json_events
FROM KAFKA CONNECTION kafka_conn (TOPIC 'events')
FORMAT JSON;

-- 注意：Materialize 支持 JSONB（不支持 JSON）
-- 注意：兼容 PostgreSQL 的 JSONB 操作符和函数
-- 注意：JSON SOURCE 自动解析 Kafka 中的 JSON 数据
-- 注意：物化视图中可以提取和转换 JSON 字段
