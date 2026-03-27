-- SQL 标准: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] ISO/IEC 9075-2:2023 - SQL/Foundation
--       https://www.iso.org/standard/76583.html
--   [2] SQL:2023 Standard - ARRAY Type
--   [3] SQL:2023 Standard - ROW Type
--   [4] SQL:2023 Standard - MULTISET Type
--   [5] SQL:2023 Standard - JSON Type (SQL/JSON)

-- ============================================================
-- ARRAY 类型（SQL:1999 引入）
-- ============================================================

-- SQL 标准的 ARRAY 定义
CREATE TABLE users (
    id     INTEGER PRIMARY KEY,
    name   VARCHAR(100),
    tags   VARCHAR(50) ARRAY[20],              -- 最大 20 个元素
    scores INTEGER ARRAY                       -- 无大小限制（SQL:2003+）
);

-- 数组构造
SELECT ARRAY[1, 2, 3];

-- 数组索引（从 1 开始，SQL 标准）
SELECT tags[1] FROM users;

-- CARDINALITY: 数组长度
SELECT CARDINALITY(tags) FROM users;

-- ARRAY_AGG: 聚合为数组（SQL:2003+）
SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees
GROUP BY department;

-- UNNEST: 展开数组为行（SQL:2003+）
SELECT u.name, t.val
FROM users u, UNNEST(u.tags) AS t(val);

-- WITH ORDINALITY（SQL:2008+）
SELECT * FROM UNNEST(ARRAY['a','b','c']) WITH ORDINALITY AS t(val, idx);

-- TRIM_ARRAY: 从末尾移除元素
SELECT TRIM_ARRAY(ARRAY[1,2,3,4,5], 2);       -- 移除最后 2 个: [1,2,3]

-- ARRAY_MAX_CARDINALITY
SELECT ARRAY_MAX_CARDINALITY(tags) FROM users;

-- 数组比较
SELECT ARRAY[1,2,3] = ARRAY[1,2,3];
SELECT ARRAY[1,2] < ARRAY[1,3];

-- ============================================================
-- ROW 类型（SQL:1999 引入）
-- ============================================================

-- ROW 类型定义（= STRUCT）
CREATE TABLE orders (
    id       INTEGER PRIMARY KEY,
    customer ROW(name VARCHAR(100), email VARCHAR(200)),
    address  ROW(street VARCHAR(200), city VARCHAR(100), zip VARCHAR(10))
);

-- ROW 构造
SELECT ROW('Alice', 'alice@example.com');

-- 访问 ROW 字段
SELECT o.customer.name FROM orders o;

-- ROW 比较
SELECT ROW(1, 'a') = ROW(1, 'a');

-- ============================================================
-- MULTISET 类型（SQL:2003+）
-- ============================================================

-- MULTISET 是无序的可重复集合
-- 类似 ARRAY 但无序
-- 注意：大多数数据库不实现 MULTISET

-- MULTISET 操作
-- MULTISET UNION / MULTISET INTERSECT / MULTISET EXCEPT
-- CARDINALITY / SET / ELEMENT

-- ============================================================
-- JSON 类型（SQL:2016 SQL/JSON）
-- ============================================================

-- SQL 标准的 JSON 支持
-- JSON_ARRAY: 构造 JSON 数组
SELECT JSON_ARRAY(1, 2, 3);
SELECT JSON_ARRAY('a', 'b', 'c');

-- JSON_OBJECT: 构造 JSON 对象
SELECT JSON_OBJECT('name' VALUE 'Alice', 'age' VALUE 30);

-- JSON_VALUE: 提取标量值
SELECT JSON_VALUE('{"name":"Alice"}', '$.name');

-- JSON_QUERY: 提取 JSON 片段
SELECT JSON_QUERY('{"tags":["a","b"]}', '$.tags');

-- JSON_TABLE: 展开 JSON（SQL:2016+）
SELECT *
FROM JSON_TABLE(
    '[{"name":"Alice","age":30},{"name":"Bob","age":25}]',
    '$[*]' COLUMNS (
        name VARCHAR(50) PATH '$.name',
        age  INTEGER     PATH '$.age'
    )
) AS jt;

-- JSON_ARRAYAGG / JSON_OBJECTAGG
SELECT JSON_ARRAYAGG(name ORDER BY name) FROM employees;
SELECT JSON_OBJECTAGG(KEY name VALUE salary) FROM employees;

-- IS JSON: 类型检查
SELECT '{"a":1}' IS JSON;
SELECT '[1,2,3]' IS JSON ARRAY;
SELECT '{"a":1}' IS JSON OBJECT;
SELECT '"hello"' IS JSON SCALAR;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. ARRAY: SQL:1999 引入，大多数数据库支持
-- 2. ROW: SQL:1999 引入，部分数据库支持
-- 3. MULTISET: SQL:2003 引入，很少有数据库实现
-- 4. JSON: SQL:2016 引入 SQL/JSON 标准
-- 5. 标准中没有 MAP 类型
-- 6. 数组下标从 1 开始（SQL 标准）
-- 7. 各数据库的实际实现可能与标准有差异
