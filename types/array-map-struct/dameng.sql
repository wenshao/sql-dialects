-- 达梦 (DM): 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] 达梦数据库 SQL 语言参考 - 数据类型
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dm-sql-data-type.html
--   [2] 达梦数据库 SQL 语言参考 - 集合类型
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-type.html

-- ============================================================
-- 达梦兼容 Oracle 的集合类型（在 PL/SQL 中使用）
-- ============================================================

-- VARRAY 类型
CREATE TYPE tag_array AS VARRAY(20) OF VARCHAR2(50);
/

-- Nested Table 类型
CREATE TYPE string_table AS TABLE OF VARCHAR2(100);
/

-- 使用 VARRAY 作为表列
CREATE TABLE users (
    id   INT PRIMARY KEY,
    name VARCHAR2(100),
    tags tag_array
);

INSERT INTO users VALUES (1, 'Alice', tag_array('admin', 'dev'));

-- TABLE() 展开
SELECT u.name, t.COLUMN_VALUE AS tag
FROM users u, TABLE(u.tags) t;

-- ============================================================
-- 对象类型（类似 STRUCT）
-- ============================================================

CREATE TYPE address_type AS OBJECT (
    street VARCHAR2(200),
    city   VARCHAR2(100),
    zip    VARCHAR2(10)
);
/

CREATE TABLE customers (
    id      INT PRIMARY KEY,
    name    VARCHAR2(100),
    address address_type
);

INSERT INTO customers VALUES (1, 'Alice',
    address_type('123 Main St', 'Springfield', '62701'));

SELECT c.address.city FROM customers c;

-- ============================================================
-- JSON（达梦 8 支持）
-- ============================================================

CREATE TABLE events (
    id   INT PRIMARY KEY,
    data CLOB CHECK (data IS JSON)
);

INSERT INTO events VALUES (1, '{"type":"click","tags":["a","b"]}');

SELECT JSON_VALUE(data, '$.type') FROM events;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 兼容 Oracle 的 VARRAY / Nested Table / Object Type
-- 2. 没有原生 MAP 类型
-- 3. 支持 JSON 函数
-- 4. 集合类型主要在 PL/SQL 中使用
