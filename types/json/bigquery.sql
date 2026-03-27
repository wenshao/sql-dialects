-- BigQuery: JSON 类型
--
-- 参考资料:
--   [1] BigQuery SQL Reference - JSON Data Type
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#json_type
--   [2] BigQuery - JSON Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/json_functions

-- ============================================================
-- 1. JSON 类型（原生类型，非 STRING）
-- ============================================================

-- BigQuery 有专用的 JSON 类型（不是 STRING 别名）:
CREATE TABLE events (
    id       INT64 NOT NULL,
    payload  JSON,              -- 专用 JSON 类型
    metadata STRING             -- 也可以用 STRING 存 JSON
);

-- 插入
INSERT INTO events VALUES (1, JSON '{"name": "alice", "age": 25}', NULL);
INSERT INTO events VALUES (2, JSON '{"name": "bob", "tags": ["vip"]}', NULL);

-- JSON 类型 vs STRING:
--   JSON 类型: 内部二进制存储，验证有效性，原生函数更高效
--   STRING: 文本存储，不验证，需要 JSON_EXTRACT 解析

-- ============================================================
-- 2. JSON 读取
-- ============================================================

-- 字段访问（点号语法，BigQuery 独有的简洁语法）
SELECT payload.name FROM events;          -- 直接点号访问!
SELECT payload.age FROM events;
SELECT payload.tags[0] FROM events;       -- 数组索引

-- JSON_VALUE（返回标量值为 STRING）
SELECT JSON_VALUE(payload, '$.name') FROM events;

-- JSON_QUERY（返回 JSON 子树）
SELECT JSON_QUERY(payload, '$.tags') FROM events;    -- ["vip"]

-- LAX vs STRICT 模式:
SELECT JSON_VALUE(payload, 'lax $.missing_field');    -- NULL（宽松）
SELECT JSON_VALUE(payload, 'strict $.missing_field'); -- 报错（严格）

-- 设计分析:
--   BigQuery 的点号访问语法（payload.name）是最简洁的 JSON 访问方式。
--   对比: PostgreSQL 需要 payload->>'name'
--         MySQL 需要 JSON_EXTRACT(payload, '$.name')
--         SQLite 需要 json_extract(payload, '$.name') 或 payload->>'$.name'

-- ============================================================
-- 3. JSON 与 STRUCT 的关系（BigQuery 独特设计）
-- ============================================================

-- BigQuery 中 JSON 和 STRUCT 都可以表示嵌套数据:
-- STRUCT: 编译时 schema 固定（强类型）
-- JSON:   运行时 schema 灵活（弱类型）
--
-- 推荐选择:
--   已知 schema → STRUCT（查询性能更好，列式存储）
--   未知/变化 schema → JSON（灵活但查询较慢）
--
-- STRUCT 示例:
-- CREATE TABLE users (
--     id INT64,
--     address STRUCT<street STRING, city STRING, zip STRING>
-- );
-- SELECT address.city FROM users;  -- 点号访问，与 JSON 语法相同

-- ============================================================
-- 4. JSON 数组操作
-- ============================================================

-- 展开 JSON 数组
SELECT id, tag
FROM events, UNNEST(JSON_QUERY_ARRAY(payload, '$.tags')) AS tag;

-- JSON 数组长度
SELECT JSON_QUERY(payload, '$.tags'),
       ARRAY_LENGTH(JSON_QUERY_ARRAY(payload, '$.tags'))
FROM events;

-- ============================================================
-- 5. JSON 构建与转换
-- ============================================================

-- 构建 JSON
SELECT JSON_OBJECT('name', 'alice', 'age', 25);
SELECT JSON_ARRAY(1, 2, 'three', NULL);
SELECT TO_JSON(STRUCT('alice' AS name, 25 AS age));

-- JSON → STRING
SELECT STRING(payload) FROM events;

-- STRING → JSON
SELECT PARSE_JSON('{"name": "alice"}');
SELECT SAFE.PARSE_JSON('invalid json');  -- NULL（安全模式）

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery JSON 的设计:
--   (1) 专用 JSON 类型 → 内部二进制存储 + 验证
--   (2) 点号访问语法 → 最简洁的 JSON 查询
--   (3) JSON vs STRUCT → 动态 vs 静态 schema 的选择
--   (4) SAFE.PARSE_JSON → 安全解析（错误返回 NULL）
--
-- 对引擎开发者的启示:
--   提供 STRUCT（静态 schema）和 JSON（动态 schema）两种嵌套类型
--   是云数仓的最佳实践。用户根据 schema 确定性选择。
--   点号访问语法（payload.field）比 -> 操作符或函数更直观，
--   应该作为 JSON 访问的首选语法。
