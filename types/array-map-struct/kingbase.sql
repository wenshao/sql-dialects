-- 人大金仓 (KingbaseES): 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] KingbaseES 文档 - 数据类型
--       https://help.kingbase.com.cn/v8/development/sql-plsql/sql/SQL_data_types.html
--   [2] KingbaseES 文档 - 数组
--       https://help.kingbase.com.cn/v8/development/sql-plsql/sql/SQL_data_types_8.html

-- ============================================================
-- KingbaseES 基于 PostgreSQL，兼容 PostgreSQL 的 ARRAY 和复合类型
-- ============================================================

-- ARRAY 类型
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],
    scores INTEGER[]
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   '{user,tester}', '{70,80}');

SELECT tags[1] FROM users;
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT * FROM users WHERE 'admin' = ANY(tags);
SELECT UNNEST(tags) FROM users;
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

-- 复合类型
CREATE TYPE address AS (street TEXT, city TEXT, zip VARCHAR(10));
CREATE TABLE customers (id SERIAL PRIMARY KEY, addr address);
INSERT INTO customers (addr) VALUES (ROW('123 Main', 'NYC', '10001'));
SELECT (addr).city FROM customers;

-- hstore
CREATE EXTENSION IF NOT EXISTS hstore;
-- 参见 postgres.sql 获取详细的 hstore 和 JSONB 用法

-- JSONB
CREATE TABLE events (id SERIAL, data JSONB);
INSERT INTO events (data) VALUES ('{"tags": ["a","b"]}');
SELECT data->'tags' FROM events;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 兼容 PostgreSQL 的 ARRAY 和复合类型
-- 2. 支持 hstore 扩展
-- 3. 支持 JSONB 类型
-- 4. 数组下标从 1 开始
-- 5. 同时支持 Oracle 兼容模式（VARRAY / Nested Table）
