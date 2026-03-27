-- PolarDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] PolarDB for MySQL 文档 - JSON 支持
--       https://help.aliyun.com/document_detail/316770.html
--   [2] PolarDB for PostgreSQL 文档 - 数据类型
--       https://help.aliyun.com/document_detail/472096.html

-- ============================================================
-- PolarDB for MySQL — JSON 类型
-- ============================================================

CREATE TABLE users (
    id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    tags JSON,
    metadata JSON
);

INSERT INTO users (name, tags) VALUES ('Alice', JSON_ARRAY('admin', 'dev'));
SELECT JSON_EXTRACT(tags, '$[0]') FROM users;
SELECT tags->'$[0]' FROM users;
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');

-- JSON_TABLE
SELECT u.name, jt.tag
FROM users u,
JSON_TABLE(u.tags, '$[*]' COLUMNS (tag VARCHAR(50) PATH '$')) AS jt;

-- 聚合
SELECT JSON_ARRAYAGG(name) FROM users;

-- ============================================================
-- PolarDB for PostgreSQL — ARRAY 和复合类型
-- ============================================================

-- ARRAY
-- CREATE TABLE users (id SERIAL, tags TEXT[], scores INT[]);
-- 完全兼容 PostgreSQL 的 ARRAY 语法，参见 postgres.sql

-- 复合类型
-- CREATE TYPE address AS (street TEXT, city TEXT, zip VARCHAR(10));

-- hstore 扩展
-- CREATE EXTENSION hstore;

-- JSONB
-- CREATE TABLE events (id SERIAL, data JSONB);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. PolarDB for MySQL 使用 JSON 替代复杂类型
-- 2. PolarDB for PostgreSQL 完全兼容 PostgreSQL 的 ARRAY/复合类型/JSONB
-- 3. 根据底层兼容的数据库选择合适的方案
