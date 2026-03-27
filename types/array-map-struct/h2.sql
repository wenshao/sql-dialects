-- H2 Database: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] H2 Documentation - Data Types (ARRAY)
--       https://www.h2database.com/html/datatypes.html#array_type
--   [2] H2 Documentation - Data Types (ROW)
--       https://www.h2database.com/html/datatypes.html#row_type
--   [3] H2 Documentation - JSON Functions
--       https://www.h2database.com/html/functions.html#json_array

-- ============================================================
-- ARRAY 类型（H2 原生支持）
-- ============================================================

CREATE TABLE users (
    id     INT AUTO_INCREMENT PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    tags   VARCHAR(50) ARRAY,                  -- 变长数组
    scores INTEGER ARRAY[10]                   -- 最大 10 个元素
);

INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   ARRAY['user', 'tester'], ARRAY[70, 80]);

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;

-- CARDINALITY: 长度
SELECT CARDINALITY(tags) FROM users;

-- ARRAY_AGG: 聚合
SELECT ARRAY_AGG(name ORDER BY name) FROM users;

-- UNNEST: 展开
SELECT u.name, t.val
FROM users u, UNNEST(u.tags) AS t(val);

-- ARRAY_CONTAINS（H2 2.0+）
SELECT * FROM users WHERE ARRAY_CONTAINS(tags, 'admin');

-- ARRAY_CAT: 连接
SELECT ARRAY_CAT(ARRAY[1,2], ARRAY[3,4]);

-- ARRAY_APPEND / ARRAY_SLICE
SELECT ARRAY_APPEND(tags, 'new') FROM users;
SELECT ARRAY_SLICE(tags, 1, 2) FROM users;

-- ============================================================
-- ROW 类型（类似 STRUCT，H2 2.0+）
-- ============================================================

CREATE TABLE orders (
    id       INT PRIMARY KEY,
    customer ROW(name VARCHAR(100), email VARCHAR(200))
);

INSERT INTO orders VALUES (1, ROW('Alice', 'alice@example.com'));

-- 访问 ROW 字段
SELECT o.customer.name FROM orders o;       -- 使用命名字段

-- ============================================================
-- JSON 函数（H2 2.0+）
-- ============================================================

SELECT JSON_ARRAY('a', 'b', 'c');
SELECT JSON_OBJECT('name': 'Alice', 'age': 30);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. H2 原生支持 ARRAY 和 ROW 类型
-- 2. 没有原生 MAP 类型
-- 3. 数组下标从 1 开始
-- 4. JSON 函数从 H2 2.0 开始支持
-- 5. 兼容 SQL 标准的数组语法
