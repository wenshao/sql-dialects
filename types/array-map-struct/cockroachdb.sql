-- CockroachDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] CockroachDB Docs - ARRAY
--       https://www.cockroachlabs.com/docs/stable/array.html
--   [2] CockroachDB Docs - JSONB
--       https://www.cockroachlabs.com/docs/stable/jsonb.html
--   [3] CockroachDB Docs - Computed Columns
--       https://www.cockroachlabs.com/docs/stable/computed-columns.html

-- ============================================================
-- ARRAY 类型（兼容 PostgreSQL）
-- ============================================================

CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   STRING NOT NULL,
    tags   STRING[],
    scores INT[]
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   ARRAY['user', 'tester'], ARRAY[70, 80, 75]);

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;

-- ARRAY 操作
SELECT ARRAY_LENGTH(tags, 1) FROM users;
SELECT ARRAY_APPEND(tags, 'new') FROM users;
SELECT ARRAY_PREPEND('first', tags) FROM users;
SELECT ARRAY_CAT(tags, ARRAY['extra']) FROM users;
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;
SELECT ARRAY_POSITION(tags, 'admin') FROM users;

-- ARRAY 操作符
SELECT * FROM users WHERE tags @> ARRAY['admin'];
SELECT * FROM users WHERE 'admin' = ANY(tags);
SELECT tags || ARRAY['new'] FROM users;

-- UNNEST
SELECT UNNEST(ARRAY[1,2,3]);
SELECT u.name, UNNEST(u.tags) AS tag FROM users u;

-- ARRAY_AGG
SELECT department, ARRAY_AGG(name ORDER BY name)
FROM employees GROUP BY department;

-- ============================================================
-- JSONB（代替 MAP / STRUCT）
-- ============================================================

CREATE TABLE products (
    id         SERIAL PRIMARY KEY,
    name       STRING,
    attributes JSONB
);

INSERT INTO products (name, attributes) VALUES
    ('Laptop', '{"brand": "Dell", "ram": "16GB", "specs": {"cpu": "i7"}}');

SELECT attributes->>'brand' FROM products;
SELECT attributes->'specs'->>'cpu' FROM products;
SELECT jsonb_object_keys(attributes) FROM products;

-- GIN 索引
CREATE INVERTED INDEX idx_attrs ON products (attributes);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 支持 PostgreSQL 风格的 ARRAY 类型
-- 2. 没有原生 MAP / STRUCT 类型，使用 JSONB
-- 3. 支持 GIN（Inverted Index）加速 JSONB 查询
-- 4. 数组下标从 1 开始
