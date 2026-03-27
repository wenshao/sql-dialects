-- PostgreSQL: 复合类型 (Array, Composite/Struct, hstore/Map)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Arrays
--       https://www.postgresql.org/docs/current/arrays.html
--   [2] PostgreSQL Documentation - Composite Types
--       https://www.postgresql.org/docs/current/rowtypes.html
--   [3] PostgreSQL Documentation - hstore
--       https://www.postgresql.org/docs/current/hstore.html

-- ============================================================
-- 1. ARRAY 类型: PostgreSQL 的一等公民
-- ============================================================

CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    tags   TEXT[],                          -- 一维文本数组
    scores INTEGER[],                      -- 一维整数数组
    matrix INTEGER[][],                    -- 多维数组
    phones VARCHAR(20) ARRAY               -- SQL 标准语法
);

INSERT INTO users (tags, scores) VALUES
    (ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('{user,tester}', '{70,80,75}');        -- 字面量语法

-- 数组下标从 1 开始（不是 0！这是 SQL 标准）
SELECT tags[1], scores[2] FROM users;
SELECT scores[1:2] FROM users;              -- 切片

-- 设计分析: 为什么 PostgreSQL 原生支持 ARRAY
--   PostgreSQL 的类型系统设计: 每种基础类型自动拥有对应的数组类型。
--   定义 CREATE TYPE point 时，PostgreSQL 自动创建 point[] 类型。
--   这与 PostgreSQL 的"一切皆可扩展"哲学一致。
--   对比: MySQL 无 ARRAY 类型（用 JSON 替代），Oracle 需要 CREATE TYPE AS VARRAY

-- ============================================================
-- 2. ARRAY 操作符（GIN 索引支持）
-- ============================================================

SELECT * FROM users WHERE tags @> ARRAY['admin'];       -- 包含
SELECT * FROM users WHERE ARRAY['admin'] <@ tags;       -- 被包含
SELECT * FROM users WHERE tags && ARRAY['admin','user'];-- 重叠（有交集）
SELECT * FROM users WHERE 'admin' = ANY(tags);          -- ANY 成员测试
SELECT ARRAY[1,2] || ARRAY[3,4];                        -- 连接: {1,2,3,4}

-- GIN 索引加速 @>, <@, && 操作
CREATE INDEX idx_tags ON users USING GIN (tags);

-- ============================================================
-- 3. ARRAY 函数
-- ============================================================

SELECT ARRAY_LENGTH(tags, 1) FROM users;               -- 第1维长度
SELECT CARDINALITY(ARRAY[1,2,3]);                      -- 总元素数 (9.4+)
SELECT ARRAY_APPEND(ARRAY[1,2], 3);                    -- {1,2,3}
SELECT ARRAY_PREPEND(0, ARRAY[1,2]);                   -- {0,1,2}
SELECT ARRAY_REMOVE(ARRAY[1,2,3,2], 2);               -- {1,3}
SELECT ARRAY_POSITION(ARRAY['a','b','c'], 'b');        -- 2 (9.5+)
SELECT ARRAY_CAT(ARRAY[1,2], ARRAY[3,4]);             -- {1,2,3,4}

-- UNNEST: 展开数组为行（PostgreSQL 最常用的数组函数）
SELECT UNNEST(ARRAY['a','b','c']);                      -- 3行
SELECT * FROM UNNEST(ARRAY['a','b','c']) WITH ORDINALITY AS t(val, idx); -- 带序号(9.4+)

-- ARRAY_AGG: 行聚合为数组
SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees GROUP BY department;

-- ============================================================
-- 4. 复合类型 (Composite Type) — 等价于 STRUCT
-- ============================================================

CREATE TYPE address AS (
    street TEXT, city TEXT, state TEXT, zip VARCHAR(10)
);

CREATE TABLE customers (
    id        SERIAL PRIMARY KEY,
    name      TEXT NOT NULL,
    home_addr address,
    work_addr address
);

-- 插入复合类型
INSERT INTO customers (name, home_addr) VALUES
    ('Alice', ROW('123 Main St', 'Springfield', 'IL', '62701'));

-- 访问字段（注意括号！）
SELECT (home_addr).city FROM customers;
SELECT (home_addr).* FROM customers;          -- 展开所有字段

-- 更新字段
UPDATE customers SET home_addr.city = 'New City' WHERE id = 1;

-- 设计分析:
--   CREATE TABLE 自动创建同名复合类型。
--   即: CREATE TABLE foo (...) 会自动注册 foo 复合类型。
--   这意味着可以写 SELECT ROW(1, 'text')::foo 将行转换为表类型。

-- ============================================================
-- 5. hstore: Key-Value Map 类型（扩展）
-- ============================================================

CREATE EXTENSION IF NOT EXISTS hstore;

CREATE TABLE products (
    id         SERIAL PRIMARY KEY,
    name       TEXT,
    attributes hstore
);

INSERT INTO products (name, attributes) VALUES
    ('Laptop', 'brand => "Dell", ram => "16GB", cpu => "i7"');

-- hstore 操作
SELECT attributes -> 'brand' FROM products;              -- 获取值
SELECT attributes ? 'ram' FROM products;                 -- 键存在?
SELECT attributes ?& ARRAY['brand','ram'] FROM products; -- 所有键存在?
SELECT akeys(attributes), avals(attributes) FROM products; -- 所有键/值
SELECT hstore_to_json(attributes) FROM products;         -- 转 JSON

-- GIN 索引
CREATE INDEX idx_attrs ON products USING GIN (attributes);

-- hstore vs JSONB:
--   hstore: 只支持 TEXT→TEXT 映射，不支持嵌套，但更轻量
--   JSONB:  支持任意类型和嵌套，功能更强，已成为主流选择
--   建议:   新项目使用 JSONB（hstore 是 JSONB 之前的方案）

-- ============================================================
-- 6. JSONB 作为通用复杂类型
-- ============================================================

CREATE TABLE events (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO events (data) VALUES (
    '{"type":"click","tags":["mobile","ios"],"metadata":{"ip":"1.2.3.4"}}'
);

-- JSONB 支持数组、对象（map）、嵌套结构
SELECT data->'tags' FROM events;               -- JSON 数组
SELECT data->'metadata'->>'ip' FROM events;    -- 嵌套字段值

-- GIN 索引
CREATE INDEX idx_data ON events USING GIN (data);
CREATE INDEX idx_data_path ON events USING GIN (data jsonb_path_ops); -- 更小更快

-- ============================================================
-- 7. 横向对比: 复合类型能力
-- ============================================================

-- 1. ARRAY:
--   PostgreSQL: 内置一等类型（所有类型自动有数组版本）
--   MySQL:      无 ARRAY 类型（用 JSON 替代）
--   Oracle:     VARRAY / NESTED TABLE（需 CREATE TYPE）
--   BigQuery:   ARRAY（内置）
--   ClickHouse: Array(T)（内置）
--
-- 2. STRUCT/复合类型:
--   PostgreSQL: CREATE TYPE AS (...)，表自动创建同名类型
--   BigQuery:   STRUCT 内置
--   ClickHouse: Tuple(...)
--   MySQL:      不支持
--
-- 3. MAP:
--   PostgreSQL: hstore（扩展）或 JSONB
--   ClickHouse: Map(K, V) 内置
--   BigQuery:   无 MAP（用 STRUCT 数组替代）
--   MySQL:      JSON

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) "每种类型自动有数组版本" 是 PostgreSQL 类型系统的精髓:
--     实现: pg_type 表中每种类型记录 typarray 字段指向数组类型。
--     新类型注册时自动创建对应数组类型。
--
-- (2) GIN 索引是数组/JSONB/hstore 高效查询的基础:
--     没有 GIN，@> 操作符只能全表扫描。
--     GIN 的倒排索引结构天然适合"包含"语义。
--
-- (3) hstore → JSONB 的演进说明:
--     专用类型（hstore）被通用类型（JSONB）取代是自然趋势。
--     JSONB 的二进制存储格式吸收了 hstore 的设计经验。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- PostgreSQL 全版本: ARRAY, 复合类型
-- PostgreSQL 8.2:   hstore 扩展
-- PostgreSQL 9.4:   CARDINALITY(), WITH ORDINALITY, JSONB 类型
-- PostgreSQL 9.5:   ARRAY_POSITION, ARRAY_POSITIONS
-- PostgreSQL 14:    JSONB 下标访问 data['key']
