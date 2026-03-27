-- Oracle: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Oracle Documentation - VARRAY Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-collections-and-records.html
--   [2] Oracle Documentation - Nested Table Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-collections-and-records.html#GUID-7E9034D5-0D33-43A1-9012-918350E5A1B0
--   [3] Oracle Documentation - Object Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/adobj/basic-components-of-oracle-objects.html
--   [4] Oracle Documentation - JSON Data Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/adjsn/

-- ============================================================
-- VARRAY 类型（固定大小数组）
-- ============================================================

-- 创建 VARRAY 类型
CREATE TYPE tag_array AS VARRAY(20) OF VARCHAR2(50);
/

CREATE TYPE score_array AS VARRAY(100) OF NUMBER;
/

-- 使用 VARRAY
CREATE TABLE users (
    id     NUMBER PRIMARY KEY,
    name   VARCHAR2(100) NOT NULL,
    tags   tag_array,
    scores score_array
);

INSERT INTO users VALUES (1, 'Alice', tag_array('admin', 'dev'), score_array(90, 85, 95));
INSERT INTO users VALUES (2, 'Bob',   tag_array('user'), score_array(70, 80));

-- ============================================================
-- Nested Table 类型（可变大小集合）
-- ============================================================

-- 创建 Nested Table 类型
CREATE TYPE string_table AS TABLE OF VARCHAR2(100);
/

CREATE TYPE number_table AS TABLE OF NUMBER;
/

CREATE TABLE products (
    id       NUMBER PRIMARY KEY,
    name     VARCHAR2(100),
    keywords string_table
) NESTED TABLE keywords STORE AS keywords_nt;

INSERT INTO products VALUES (1, 'Laptop', string_table('computer', 'electronics', 'tech'));

-- ============================================================
-- 集合操作
-- ============================================================

-- TABLE() 函数: 展开集合为行（= UNNEST）
SELECT u.name, t.COLUMN_VALUE AS tag
FROM users u, TABLE(u.tags) t;

-- CARDINALITY: 集合大小
SELECT CARDINALITY(tags) FROM users;

-- MEMBER OF: 元素检查
SELECT * FROM users WHERE 'admin' MEMBER OF tags;

-- MULTISET 操作（Nested Table）
-- MULTISET UNION
SELECT string_table('a','b') MULTISET UNION string_table('b','c') FROM DUAL;
-- MULTISET INTERSECT
SELECT string_table('a','b','c') MULTISET INTERSECT string_table('b','c','d') FROM DUAL;
-- MULTISET EXCEPT
SELECT string_table('a','b','c') MULTISET EXCEPT string_table('b') FROM DUAL;

-- SET: 去重
SELECT SET(string_table('a','b','a','c')) FROM DUAL;

-- ============================================================
-- Object Type（类似 STRUCT）
-- ============================================================

-- 创建对象类型
CREATE TYPE address_type AS OBJECT (
    street  VARCHAR2(200),
    city    VARCHAR2(100),
    state   VARCHAR2(50),
    zip     VARCHAR2(10)
);
/

CREATE TYPE contact_type AS OBJECT (
    email VARCHAR2(200),
    phone VARCHAR2(20)
);
/

-- 使用对象类型
CREATE TABLE customers (
    id        NUMBER PRIMARY KEY,
    name      VARCHAR2(100),
    home_addr address_type,
    contact   contact_type
);

INSERT INTO customers VALUES (
    1, 'Alice',
    address_type('123 Main St', 'Springfield', 'IL', '62701'),
    contact_type('alice@example.com', '555-0100')
);

-- 访问对象字段
SELECT c.home_addr.city, c.contact.email FROM customers c;

-- 更新对象字段
UPDATE customers c SET c.home_addr.city = 'Chicago' WHERE c.id = 1;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- 对象类型的数组
CREATE TYPE address_array AS VARRAY(10) OF address_type;
/

CREATE TABLE orders (
    id         NUMBER PRIMARY KEY,
    addresses  address_array
);

INSERT INTO orders VALUES (1, address_array(
    address_type('123 Main St', 'NYC', 'NY', '10001'),
    address_type('456 Oak Ave', 'LA', 'CA', '90001')
));

-- 展开
SELECT o.id, a.*
FROM orders o, TABLE(o.addresses) a;

-- ============================================================
-- COLLECT: 聚合为集合（= ARRAY_AGG）
-- ============================================================

SELECT department, COLLECT(name) AS members
FROM employees
GROUP BY department;

-- CAST + MULTISET
SELECT CAST(MULTISET(
    SELECT name FROM employees WHERE department = 'IT'
) AS string_table) FROM DUAL;

-- ============================================================
-- JSON 类型（Oracle 21c+）
-- ============================================================

-- Oracle 21c+ 原生 JSON 数据类型
CREATE TABLE events (
    id   NUMBER PRIMARY KEY,
    data JSON
);

INSERT INTO events VALUES (1, '{"type": "click", "tags": ["mobile", "ios"]}');

-- JSON_VALUE: 提取标量值
SELECT JSON_VALUE(data, '$.type') FROM events;

-- JSON_QUERY: 提取 JSON 片段
SELECT JSON_QUERY(data, '$.tags') FROM events;

-- JSON_TABLE: 展开 JSON（Oracle 12c+）
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$'
    COLUMNS (
        event_type VARCHAR2(50) PATH '$.type',
        NESTED PATH '$.tags[*]'
            COLUMNS (tag VARCHAR2(50) PATH '$')
    )
) jt;

-- JSON_ARRAYAGG / JSON_OBJECTAGG（Oracle 12c Release 2+）
SELECT JSON_ARRAYAGG(name ORDER BY name) FROM employees;
SELECT JSON_OBJECTAGG(name VALUE salary) FROM employees;

-- JSON 点表示法（Oracle 12c+，简化的 JSON 列访问）
-- 需要在建表时声明 IS JSON 约束
CREATE TABLE logs (
    id   NUMBER PRIMARY KEY,
    data VARCHAR2(4000) CONSTRAINT chk_json CHECK (data IS JSON)
);

SELECT l.data.type FROM logs l;               -- 简化访问

-- ============================================================
-- MAP 替代方案
-- ============================================================

-- 方案 1: 使用对象类型
-- 方案 2: 使用 JSON 对象
-- 方案 3: 使用关联数组（仅 PL/SQL）

-- PL/SQL 关联数组（MAP 最接近的实现）
-- 注意：关联数组只能在 PL/SQL 中使用，不能作为表列
DECLARE
    TYPE string_map IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(50);
    settings string_map;
BEGIN
    settings('theme') := 'dark';
    settings('lang')  := 'en';
    DBMS_OUTPUT.PUT_LINE(settings('theme'));
END;
/

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Oracle 使用 VARRAY 和 Nested Table 替代 ARRAY
-- 2. Object Type 提供 STRUCT 功能
-- 3. 没有原生 MAP 类型（PL/SQL 关联数组只在 PL/SQL 中可用）
-- 4. JSON 类型 (21c+) 提供灵活的复杂类型支持
-- 5. JSON_TABLE (12c+) 提供强大的 JSON 展开功能
-- 6. VARRAY 有大小限制，Nested Table 无限制
-- 7. TABLE() 函数用于展开集合
