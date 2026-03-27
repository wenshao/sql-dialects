-- PostgreSQL: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Arrays
--       https://www.postgresql.org/docs/current/arrays.html
--   [2] PostgreSQL Documentation - Composite Types
--       https://www.postgresql.org/docs/current/rowtypes.html
--   [3] PostgreSQL Documentation - hstore (Key-Value)
--       https://www.postgresql.org/docs/current/hstore.html
--   [4] PostgreSQL Documentation - JSON Types
--       https://www.postgresql.org/docs/current/datatype-json.html
--   [5] PostgreSQL Documentation - Array Functions
--       https://www.postgresql.org/docs/current/functions-array.html

-- ============================================================
-- ARRAY 类型
-- ============================================================

-- 定义数组列
CREATE TABLE users (
    id       SERIAL PRIMARY KEY,
    name     TEXT NOT NULL,
    tags     TEXT[],                        -- 一维文本数组
    scores   INTEGER[],                     -- 一维整数数组
    matrix   INTEGER[][],                   -- 多维数组
    phones   VARCHAR(20) ARRAY              -- SQL 标准语法
);

-- 插入数组数据
INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   '{user,tester}', '{70,80,75}'),           -- 字面量语法
    ('Carol', ARRAY['dev'], ARRAY[88]);

-- 数组索引（PostgreSQL 数组下标从 1 开始）
SELECT tags[1] FROM users;                  -- 第一个元素
SELECT scores[2] FROM users;               -- 第二个元素

-- 数组切片
SELECT scores[1:2] FROM users;             -- 前两个元素
SELECT scores[2:] FROM users;              -- 从第二个到末尾

-- ============================================================
-- ARRAY 操作函数
-- ============================================================

-- ARRAY_LENGTH: 数组长度
SELECT ARRAY_LENGTH(tags, 1) FROM users;    -- 第 1 维的长度

-- ARRAY_DIMS: 数组维度
SELECT ARRAY_DIMS(scores) FROM users;       -- 例如 '[1:3]'

-- ARRAY_CAT: 连接数组
SELECT ARRAY_CAT(ARRAY[1,2], ARRAY[3,4]);  -- {1,2,3,4}

-- ARRAY_APPEND / ARRAY_PREPEND: 追加/前插
SELECT ARRAY_APPEND(ARRAY[1,2], 3);         -- {1,2,3}
SELECT ARRAY_PREPEND(0, ARRAY[1,2]);        -- {0,1,2}

-- ARRAY_REMOVE: 移除元素
SELECT ARRAY_REMOVE(ARRAY[1,2,3,2], 2);     -- {1,3}

-- ARRAY_REPLACE: 替换元素
SELECT ARRAY_REPLACE(ARRAY[1,2,3], 2, 99);  -- {1,99,3}

-- ARRAY_POSITION: 查找元素位置（PostgreSQL 9.5+）
SELECT ARRAY_POSITION(ARRAY['a','b','c'], 'b');  -- 2

-- ARRAY_POSITIONS: 查找所有位置（PostgreSQL 9.5+）
SELECT ARRAY_POSITIONS(ARRAY[1,2,1,3,1], 1);     -- {1,3,5}

-- CARDINALITY: 数组总元素数（PostgreSQL 9.4+）
SELECT CARDINALITY(ARRAY[1,2,3]);            -- 3

-- ============================================================
-- ARRAY 操作符
-- ============================================================

-- @>: 包含
SELECT * FROM users WHERE tags @> ARRAY['admin'];

-- <@: 被包含
SELECT * FROM users WHERE ARRAY['admin'] <@ tags;

-- &&: 重叠（有共同元素）
SELECT * FROM users WHERE tags && ARRAY['admin', 'user'];

-- ||: 连接
SELECT ARRAY[1,2] || ARRAY[3,4];            -- {1,2,3,4}
SELECT ARRAY[1,2] || 3;                     -- {1,2,3}

-- = / <> / < / >: 比较
SELECT ARRAY[1,2,3] = ARRAY[1,2,3];         -- true

-- ANY / ALL: 与数组元素比较
SELECT * FROM users WHERE 'admin' = ANY(tags);
SELECT * FROM users WHERE 90 <= ALL(scores);

-- ============================================================
-- UNNEST: 展开数组为行
-- ============================================================

SELECT UNNEST(ARRAY[1,2,3]) AS val;
-- 结果: 1, 2, 3 (三行)

-- WITH ORDINALITY（PostgreSQL 9.4+）: 带序号展开
SELECT * FROM UNNEST(ARRAY['a','b','c']) WITH ORDINALITY AS t(val, idx);

-- 多数组同时展开
SELECT * FROM UNNEST(
    ARRAY['a','b','c'],
    ARRAY[1,2,3]
) AS t(letter, number);

-- ============================================================
-- ARRAY_AGG: 聚合为数组
-- ============================================================

SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees
GROUP BY department;

-- 去重
SELECT ARRAY_AGG(DISTINCT tag) FROM (SELECT UNNEST(tags) AS tag FROM users) t;

-- ============================================================
-- 复合类型 (Composite / ROW Type) — 类似 STRUCT
-- ============================================================

-- 创建自定义复合类型
CREATE TYPE address AS (
    street  TEXT,
    city    TEXT,
    state   TEXT,
    zip     VARCHAR(10)
);

-- 使用复合类型
CREATE TABLE customers (
    id         SERIAL PRIMARY KEY,
    name       TEXT NOT NULL,
    home_addr  address,
    work_addr  address
);

-- 插入复合类型数据
INSERT INTO customers (name, home_addr, work_addr) VALUES
    ('Alice', ROW('123 Main St', 'Springfield', 'IL', '62701'),
             ROW('456 Oak Ave', 'Chicago', 'IL', '60601'));

-- 字面量语法
INSERT INTO customers (name, home_addr) VALUES
    ('Bob', '("789 Elm St","Portland","OR","97201")');

-- 访问复合类型字段
SELECT (home_addr).city FROM customers;
SELECT (home_addr).* FROM customers;        -- 展开所有字段

-- 更新复合类型字段
UPDATE customers SET home_addr.city = 'New City' WHERE id = 1;

-- ============================================================
-- ROW 构造器
-- ============================================================

SELECT ROW('John', 30, 'NYC');
SELECT ROW(1, 'text', TRUE) = ROW(1, 'text', TRUE);  -- true

-- ============================================================
-- MAP 类型替代方案: hstore
-- ============================================================

-- 启用 hstore 扩展
CREATE EXTENSION IF NOT EXISTS hstore;

-- hstore 列
CREATE TABLE products (
    id         SERIAL PRIMARY KEY,
    name       TEXT,
    attributes hstore
);

INSERT INTO products (name, attributes) VALUES
    ('Laptop', 'brand => "Dell", ram => "16GB", cpu => "i7"'),
    ('Phone',  'brand => "Apple", storage => "128GB"');

-- 访问键值
SELECT attributes -> 'brand' FROM products;        -- 获取值
SELECT attributes ? 'ram' FROM products;           -- 键是否存在
SELECT attributes ?& ARRAY['brand','ram'] FROM products;  -- 所有键存在
SELECT attributes ?| ARRAY['brand','ram'] FROM products;  -- 任意键存在

-- hstore 函数
SELECT akeys(attributes) FROM products;            -- 所有键（数组）
SELECT avals(attributes) FROM products;            -- 所有值（数组）
SELECT each(attributes) FROM products;             -- 展开为行
SELECT hstore_to_json(attributes) FROM products;   -- 转为 JSON

-- ============================================================
-- JSON / JSONB 作为复杂类型替代
-- ============================================================

CREATE TABLE events (
    id      SERIAL PRIMARY KEY,
    data    JSONB NOT NULL
);

INSERT INTO events (data) VALUES
    ('{"type": "click", "tags": ["mobile", "ios"], "metadata": {"ip": "1.2.3.4"}}');

-- JSONB 支持数组、对象（map）、嵌套结构
SELECT data->'tags' FROM events;                   -- JSON 数组
SELECT data->'tags'->>0 FROM events;               -- 第一个标签
SELECT data->'metadata'->>'ip' FROM events;        -- 嵌套字段

-- ============================================================
-- 嵌套类型
-- ============================================================

-- 数组的数组
SELECT ARRAY[ARRAY[1,2], ARRAY[3,4]];

-- 复合类型数组
CREATE TABLE orders (
    id     SERIAL PRIMARY KEY,
    items  address[]                                -- 复合类型数组
);

-- JSONB 嵌套（最灵活）
CREATE TABLE documents (
    id   SERIAL PRIMARY KEY,
    doc  JSONB
);

INSERT INTO documents (doc) VALUES ('{
    "users": [
        {"name": "Alice", "roles": ["admin", "dev"]},
        {"name": "Bob", "roles": ["user"]}
    ],
    "settings": {"theme": "dark", "lang": "en"}
}');

-- ============================================================
-- GIN 索引支持
-- ============================================================

-- 数组上的 GIN 索引
CREATE INDEX idx_tags ON users USING GIN (tags);

-- hstore 上的 GIN 索引
CREATE INDEX idx_attrs ON products USING GIN (attributes);

-- JSONB 上的 GIN 索引
CREATE INDEX idx_data ON events USING GIN (data);
CREATE INDEX idx_data_path ON events USING GIN (data jsonb_path_ops);
