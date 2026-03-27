-- Vertica: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Vertica Documentation - ARRAY Types
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/DataTypes/ARRAY.htm
--   [2] Vertica Documentation - MAP Types
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/DataTypes/MAP.htm
--   [3] Vertica Documentation - ROW Types
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/DataTypes/ROW.htm
--   [4] Vertica Documentation - Complex Type Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/ComplexTypeFunctions.htm

-- ============================================================
-- ARRAY 类型（Vertica 9.1+）
-- ============================================================

CREATE TABLE users (
    id     INT PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    tags   ARRAY[VARCHAR(50)],                 -- 一维数组
    scores ARRAY[INT]
);

-- 使用 Flex 表或外部表加载数组数据

-- 数组构造（使用 ARRAY 构造器）
SELECT ARRAY['admin', 'dev'] AS tags;

-- 数组索引（从 0 开始）
SELECT tags[0] FROM users;

-- ============================================================
-- ARRAY 函数
-- ============================================================

-- ARRAY_LENGTH: 长度
SELECT ARRAY_LENGTH(tags) FROM users;

-- ARRAY_CONTAINS: 包含检查（Vertica 10.0+）
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;

-- ARRAY_CAT: 连接
SELECT ARRAY_CAT(tags, ARRAY['new']) FROM users;

-- ARRAY_FIND: 查找位置
SELECT ARRAY_FIND(tags, 'admin') FROM users;

-- EXPLODE: 展开为行
SELECT u.name, t.value AS tag
FROM users u, LATERAL EXPLODE(u.tags) t;

-- IMPLODE: 聚合为数组（= ARRAY_AGG）
-- 或使用 STRING_TO_ARRAY / SPLIT_PART 等

-- ============================================================
-- MAP 类型（Vertica 9.3+）
-- ============================================================

CREATE TABLE products (
    id         INT PRIMARY KEY,
    name       VARCHAR(100),
    attributes MAP<VARCHAR(50), VARCHAR(200)>
);

-- Map 访问
SELECT attributes['brand'] FROM products;

-- MAPKEYS / MAPVALUES
SELECT MAPKEYS(attributes) FROM products;
SELECT MAPVALUES(attributes) FROM products;

-- MAPCONTAINSKEY / MAPCONTAINSVALUE
SELECT MAPCONTAINSKEY(attributes, 'brand') FROM products;
SELECT MAPCONTAINSVALUE(attributes, 'Dell') FROM products;

-- MAPSIZE: Map 大小
SELECT MAPSIZE(attributes) FROM products;

-- Map 展开
SELECT p.name, kv.key, kv.value
FROM products p, LATERAL EXPLODE(p.attributes) kv;

-- ============================================================
-- ROW 类型（Vertica 9.1+）
-- ============================================================

CREATE TABLE orders (
    id       INT PRIMARY KEY,
    customer ROW(name VARCHAR(100), email VARCHAR(200)),
    address  ROW(street VARCHAR(200), city VARCHAR(100), state VARCHAR(50))
);

-- 访问 ROW 字段
SELECT (customer).name, (address).city FROM orders;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of ROW
CREATE TABLE events (
    id    INT,
    items ARRAY[ROW(name VARCHAR(100), qty INT, price FLOAT)]
);

-- MAP of ARRAY
CREATE TABLE configs (
    id       INT,
    settings MAP<VARCHAR(50), ARRAY[VARCHAR(100)]>
);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Vertica 原生支持 ARRAY、MAP、ROW 类型（9.1+）
-- 2. 复杂类型主要用于 Flex 表和外部数据加载
-- 3. EXPLODE 展开数组和 Map
-- 4. 数组下标从 0 开始
-- 5. 内部表的复杂类型有大小限制
