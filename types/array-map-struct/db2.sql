-- DB2: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] IBM Db2 Documentation - ARRAY Data Type
--       https://www.ibm.com/docs/en/db2/11.5?topic=types-array-data-type
--   [2] IBM Db2 Documentation - ROW Data Type
--       https://www.ibm.com/docs/en/db2/11.5?topic=types-row-data-type
--   [3] IBM Db2 Documentation - JSON Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-json

-- ============================================================
-- ARRAY 类型（Db2 10.5+）
-- ============================================================

-- 创建数组类型
CREATE TYPE string_array AS VARCHAR(100) ARRAY[100];
CREATE TYPE int_array AS INTEGER ARRAY[1000];

-- 使用数组类型的表
CREATE TABLE users (
    id     INTEGER NOT NULL PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    tags   VARCHAR(100) ARRAY[20],
    scores INTEGER ARRAY[50]
);

-- 插入数组
INSERT INTO users VALUES
    (1, 'Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    (2, 'Bob',   ARRAY['user', 'tester'], ARRAY[70, 80]);

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;

-- CARDINALITY: 数组长度
SELECT CARDINALITY(tags) FROM users;

-- TRIM_ARRAY: 从末尾移除元素
SELECT TRIM_ARRAY(scores, 1) FROM users;     -- 移除最后 1 个元素

-- ARRAY_AGG: 聚合为数组
SELECT department, ARRAY_AGG(name)
FROM employees GROUP BY department;

-- UNNEST: 展开数组
SELECT u.name, t.tag
FROM users u, UNNEST(u.tags) AS t(tag);

-- ============================================================
-- ROW 类型（结构类型）
-- ============================================================

-- 创建 ROW 类型
CREATE TYPE address_row AS ROW (
    street VARCHAR(200),
    city   VARCHAR(100),
    state  VARCHAR(50),
    zip    VARCHAR(10)
);

CREATE TABLE customers (
    id      INTEGER PRIMARY KEY,
    name    VARCHAR(100),
    address address_row
);

-- ROW 构造
INSERT INTO customers VALUES
    (1, 'Alice', ROW('123 Main St', 'Springfield', 'IL', '62701'));

-- 访问 ROW 字段
SELECT c.address..city FROM customers c;      -- Db2 双点语法

-- ============================================================
-- JSON 函数（Db2 11.1+）
-- ============================================================

-- JSON_ARRAY / JSON_OBJECT
SELECT JSON_ARRAY('a', 'b', 'c') FROM SYSIBM.SYSDUMMY1;
SELECT JSON_OBJECT(KEY 'name' VALUE 'Alice', KEY 'age' VALUE 30);

-- JSON_VALUE / JSON_QUERY
SELECT JSON_VALUE('{"name":"Alice"}', '$.name') FROM SYSIBM.SYSDUMMY1;

-- JSON_TABLE
SELECT jt.*
FROM JSON_TABLE('{"items":[{"name":"A","qty":1},{"name":"B","qty":2}]}',
    '$.items[*]' COLUMNS (
        name VARCHAR(50) PATH '$.name',
        qty  INTEGER     PATH '$.qty'
    )
) AS jt;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Db2 支持原生 ARRAY 类型（固定最大大小）
-- 2. ROW 类型提供 STRUCT 功能
-- 3. 没有原生 MAP 类型
-- 4. JSON 函数从 Db2 11.1 开始支持
-- 5. 数组下标从 1 开始
-- 6. ARRAY 类型主要在 SQL PL 存储过程中使用
