-- openGauss: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] openGauss 文档 - 数组类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/ARRAY.html
--   [2] openGauss 文档 - 复合类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-TYPE.html
--   [3] openGauss 文档 - JSON/JSONB 类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/JSON-JSONB.html

-- ============================================================
-- openGauss 基于 PostgreSQL，兼容 ARRAY 和复合类型
-- ============================================================

-- ARRAY 类型
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],
    scores INTEGER[]
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]);

SELECT tags[1] FROM users;
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT UNNEST(tags) FROM users;
SELECT ARRAY_AGG(name) FROM users;

-- 复合类型
CREATE TYPE address AS (street TEXT, city TEXT, zip VARCHAR(10));

-- JSON/JSONB
CREATE TABLE events (id SERIAL, data JSONB);
INSERT INTO events (data) VALUES ('{"tags": ["a", "b"]}');
SELECT data->'tags' FROM events;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 基于 PostgreSQL 9.2，兼容 ARRAY 和复合类型
-- 2. 支持 JSONB 类型
-- 3. 数组下标从 1 开始
-- 4. hstore 扩展可能需要单独安装
