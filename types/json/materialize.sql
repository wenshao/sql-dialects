-- Materialize: JSON 类型
-- Materialize supports JSONB type (PostgreSQL compatible) for streaming SQL.
--
-- 参考资料:
--   [1] Materialize Documentation - JSONB
--       https://materialize.com/docs/sql/types/jsonb/
--   [2] Materialize Documentation - Data Types
--       https://materialize.com/docs/sql/types/
--   [3] PostgreSQL Documentation - JSON Types (reference for compatibility)
--       https://www.postgresql.org/docs/current/datatype-json.html

-- ============================================================
-- 1. JSONB 类型概述
-- ============================================================

-- Materialize 仅支持 JSONB 类型（不支持 JSON 文本类型）
-- JSONB 是二进制格式的 JSON，插入时验证并解析
-- 兼容 PostgreSQL 的 JSONB 操作符和函数
CREATE TABLE events (
    id      INT,
    payload JSONB
);

-- ============================================================
-- 2. JSON 数据输入
-- ============================================================

-- 直接插入 JSON 文本（自动转换为 JSONB）
INSERT INTO events VALUES (1, '{"name": "alice", "age": 25, "tags": ["vip"]}');
INSERT INTO events VALUES (2, '{"name": "bob", "age": 30}');

-- 显式类型转换
INSERT INTO events VALUES (3, '{"nested": {"key": "value"}}'::JSONB);

-- 从 Kafka SOURCE 自动解析 JSON
CREATE SOURCE json_events
FROM KAFKA CONNECTION kafka_conn (TOPIC 'events')
FORMAT JSON;                                     -- 自动将 JSON 消息解析为 JSONB

-- ============================================================
-- 3. JSON 字段读取
-- ============================================================

-- 基本访问操作符（与 PostgreSQL 兼容）
SELECT payload->'name' FROM events;               -- JSONB 值: "alice"（带引号）
SELECT payload->>'name' FROM events;              -- TEXT 值: alice（不带引号）

-- 嵌套访问
SELECT payload->'nested'->'key' FROM events;      -- 深层嵌套
SELECT payload#>>'{nested,key}' FROM events;       -- 路径访问（文本）

-- 数组访问
SELECT payload->'tags'->0 FROM events;             -- 数组第一个元素

-- 类型转换
SELECT (payload->>'age')::INT FROM events;         -- 转为整数
SELECT (payload->>'age')::FLOAT FROM events;       -- 转为浮点数

-- ============================================================
-- 4. JSON 查询条件
-- ============================================================

-- 等值比较
SELECT * FROM events WHERE payload->>'name' = 'alice';

-- 包含操作符
SELECT * FROM events WHERE payload @> '{"name": "alice"}'::JSONB;

-- 键存在检查
SELECT * FROM events WHERE payload ? 'name';

-- 类型检查
SELECT * FROM events WHERE jsonb_typeof(payload->'age') = 'number';

-- ============================================================
-- 5. JSON 构造函数
-- ============================================================

-- 构造对象
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_object('id', id, 'data', payload) FROM events;

-- 构造数组
SELECT jsonb_build_array(1, 2, 3);
SELECT jsonb_build_array(payload->>'name', payload->>'age') FROM events;

-- 将行转为 JSON
SELECT to_jsonb(ROW('alice', 25));

-- ============================================================
-- 6. JSON 展开
-- ============================================================

-- 展开对象为 key-value 行
SELECT * FROM jsonb_each('{"a": 1, "b": 2}'::JSONB);
SELECT * FROM jsonb_each_text('{"a": 1, "b": 2}'::JSONB);

-- 展开数组
SELECT * FROM jsonb_array_elements('[1, 2, 3]'::JSONB);
SELECT * FROM jsonb_array_elements_text('["a", "b", "c"]'::JSONB);

-- 获取键列表
SELECT jsonb_object_keys(payload) FROM events;

-- ============================================================
-- 7. JSON 聚合
-- ============================================================

-- 聚合为 JSON 数组
SELECT jsonb_agg(payload->'name') FROM events;             -- ["alice", "bob"]

-- 聚合为 JSON 对象
SELECT jsonb_object_agg(id, payload) FROM events;

-- 去重聚合
SELECT jsonb_agg(DISTINCT payload->>'name') FROM events;

-- ============================================================
-- 8. 物化视图中的 JSON 处理
-- ============================================================

-- 物化视图: 预计算 JSON 字段提取，加速后续查询
CREATE MATERIALIZED VIEW user_summary AS
SELECT
    id,
    payload->>'name' AS name,
    (payload->>'age')::INT AS age,
    jsonb_array_length(payload->'tags') AS tag_count
FROM events;

-- 查询物化视图（直接使用预计算的列，无需重复解析 JSON）
SELECT * FROM user_summary WHERE age > 25;

-- 物化视图持续更新: SOURCE 中的新数据自动反映到物化视图
-- 这是 Materialize 的核心特性: 流式物化视图

-- ============================================================
-- 9. 流式 JSON 处理模式
-- ============================================================

-- 模式1: JSON SOURCE + 过滤
CREATE MATERIALIZED VIEW vip_events AS
SELECT id, payload->>'name' AS name
FROM events
WHERE payload @> '{"tags": ["vip"]}'::JSONB;

-- 模式2: JSON 展开为数组行
CREATE MATERIALIZED VIEW event_tags AS
SELECT
    id,
    jsonb_array_elements_text(payload->'tags') AS tag
FROM events;

-- 模式3: JSON 聚合统计
CREATE MATERIALIZED VIEW tag_stats AS
SELECT
    tag,
    COUNT(*) AS event_count
FROM (
    SELECT jsonb_array_elements_text(payload->'tags') AS tag
    FROM events
) sub
GROUP BY tag;

-- ============================================================
-- 10. Materialize 与 PostgreSQL JSONB 的差异
-- ============================================================

-- 相同点:
--   操作符: ->, ->>, #>, #>>, @>, ?, ?&, ?|
--   函数: jsonb_build_object, jsonb_agg, jsonb_each, jsonb_array_elements
--   类型: 只有 JSONB（无 JSON 文本类型）
--
-- 差异点:
--   1. Materialize 不支持 JSON 文本类型（只有 JSONB）
--   2. Materialize 的 JSONB 不支持 GIN 索引
--      （使用物化视图替代索引来加速查询）
--   3. Materialize 不支持 JSONB 修改操作（||, -, jsonb_set）
--      （流式处理模式: 新数据覆盖旧数据，而非原地修改）
--   4. Materialize 不支持 jsonb_insert, jsonb_set
--   5. Materialize 支持 Kafka/Debezium SOURCE 直接摄入 JSON

-- ============================================================
-- 11. 性能考虑
-- ============================================================

-- Materialize 的 JSON 性能特点:
--   1. JSONB 解析在摄入时完成（SOURCE 层），查询时使用二进制格式
--   2. 物化视图预计算避免重复解析 JSON
--   3. 没有 GIN 索引，复杂 JSON 查询依赖物化视图
--   4. 流式处理模式下 JSON 文档大小直接影响吞吐量
--   5. 建议: SOURCE 层尽早过滤不需要的 JSON 字段

-- ============================================================
-- 12. 注意事项与最佳实践
-- ============================================================

-- 1. 仅支持 JSONB 类型（不支持 JSON 文本类型）
-- 2. 兼容 PostgreSQL 的 JSONB 操作符和函数
-- 3. 使用物化视图替代索引来加速 JSON 查询
-- 4. 不支持 JSONB 原地修改操作（流式模式，数据不可变）
-- 5. Kafka SOURCE 支持 FORMAT JSON 自动解析
-- 6. 建议在物化视图中预提取高频 JSON 字段
-- 7. JSON 文档大小影响摄入吞吐量，建议控制在合理范围
-- 8. jsonb_typeof() 可检查 JSON 值类型（number, string, array, object 等）
