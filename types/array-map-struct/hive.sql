-- Hive: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Apache Hive Documentation - Complex Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types#LanguageManualTypes-ComplexTypes
--   [2] Apache Hive Documentation - Built-in Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
--   [3] Apache Hive Documentation - LATERAL VIEW
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
)
STORED AS ORC;

-- 插入数组数据
INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95)),
    (2, 'Bob',   ARRAY('user', 'tester'), ARRAY(70, 80, 75));

-- 数组索引（从 0 开始）
SELECT tags[0] FROM users;                    -- 第一个元素
SELECT scores[2] FROM users;                  -- 第三个元素

-- ============================================================
-- ARRAY 函数
-- ============================================================

-- SIZE / ARRAY_LENGTH: 长度
SELECT SIZE(tags) FROM users;

-- ARRAY_CONTAINS: 包含检查
SELECT * FROM users WHERE ARRAY_CONTAINS(tags, 'admin');

-- SORT_ARRAY: 排序
SELECT SORT_ARRAY(scores) FROM users;

-- CONCAT: 数组连接（Hive 2.0+）
SELECT CONCAT(tags, ARRAY('new_tag')) FROM users;

-- ARRAY_DISTINCT: 去重（Hive 2.2+）
SELECT ARRAY_DISTINCT(ARRAY(1, 2, 2, 3)) AS result;

-- ARRAY_UNION: 合并（Hive 2.2+）
SELECT ARRAY_UNION(ARRAY(1, 2), ARRAY(2, 3)) AS result;

-- ARRAY_INTERSECT: 交集（Hive 2.2+）
SELECT ARRAY_INTERSECT(ARRAY(1, 2, 3), ARRAY(2, 3, 4)) AS result;

-- ARRAY_EXCEPT: 差集（Hive 2.2+）
SELECT ARRAY_EXCEPT(ARRAY(1, 2, 3), ARRAY(2)) AS result;

-- ARRAY_JOIN: 转为字符串（Hive 3.0+）
SELECT ARRAY_JOIN(tags, ', ') FROM users;

-- ARRAY_POSITION: 查找位置（Hive 3.0+）
SELECT ARRAY_POSITION(tags, 'admin') FROM users;

-- ARRAY_REMOVE: 移除元素（Hive 3.0+）
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;

-- ============================================================
-- EXPLODE / LATERAL VIEW: 展开数组为行（= UNNEST）
-- ============================================================

-- EXPLODE: 将数组展开为多行
SELECT EXPLODE(tags) AS tag FROM users;

-- LATERAL VIEW: 与原表关联
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER: 保留空数组的行
SELECT u.name, t.tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- POSEXPLODE: 带位置展开
SELECT u.name, t.pos, t.tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- 多个 LATERAL VIEW
SELECT u.name, t.tag, s.score
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag
LATERAL VIEW EXPLODE(u.scores) s AS score;

-- ============================================================
-- COLLECT_LIST / COLLECT_SET: 聚合为数组（= ARRAY_AGG）
-- ============================================================

SELECT department, COLLECT_LIST(name) AS members
FROM employees
GROUP BY department;

-- 去重版本
SELECT department, COLLECT_SET(name) AS unique_members
FROM employees
GROUP BY department;

-- ============================================================
-- MAP 类型
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
)
STORED AS ORC;

INSERT INTO products VALUES
    (1, 'Laptop',
     MAP('brand', 'Dell', 'ram', '16GB', 'cpu', 'i7'),
     MAP('price', 999.99, 'weight', 2.1));

-- Map 访问
SELECT attributes['brand'] FROM products;     -- 获取值

-- Map 函数
SELECT MAP_KEYS(attributes) FROM products;    -- 所有键 -> ARRAY<STRING>
SELECT MAP_VALUES(attributes) FROM products;  -- 所有值 -> ARRAY<STRING>
SELECT SIZE(attributes) FROM products;        -- Map 大小

-- Map 展开
SELECT p.name, mk.key, mk.value
FROM products p
LATERAL VIEW EXPLODE(p.attributes) mk AS key, value;

-- Map 构造
SELECT MAP('k1', 'v1', 'k2', 'v2');

-- STR_TO_MAP: 字符串转 Map
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');

-- ============================================================
-- STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<street: STRING, city: STRING, state: STRING, zip: STRING>
)
STORED AS ORC;

INSERT INTO orders VALUES (
    1,
    NAMED_STRUCT('name', 'Alice', 'email', 'alice@example.com'),
    NAMED_STRUCT('street', '123 Main St', 'city', 'Springfield', 'state', 'IL', 'zip', '62701')
);

-- 访问 STRUCT 字段
SELECT customer.name, customer.email FROM orders;
SELECT address.city, address.zip FROM orders;

-- STRUCT 构造
SELECT STRUCT('Alice', 30);                           -- 匿名
SELECT NAMED_STRUCT('name', 'Alice', 'age', 30);     -- 命名

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of STRUCT
CREATE TABLE events (
    id    BIGINT,
    items ARRAY<STRUCT<product_id: BIGINT, name: STRING, qty: INT, price: DOUBLE>>
)
STORED AS ORC;

INSERT INTO events VALUES (1, ARRAY(
    NAMED_STRUCT('product_id', 1L, 'name', 'Widget', 'qty', 2, 'price', 9.99),
    NAMED_STRUCT('product_id', 2L, 'name', 'Gadget', 'qty', 1, 'price', 29.99)
));

-- 查询嵌套
SELECT e.id, item.name, item.price
FROM events e
LATERAL VIEW EXPLODE(e.items) t AS item;

-- MAP of ARRAY
CREATE TABLE configs (
    id       BIGINT,
    settings MAP<STRING, ARRAY<STRING>>
)
STORED AS ORC;

-- ARRAY of MAP
CREATE TABLE logs (
    id      BIGINT,
    entries ARRAY<MAP<STRING, STRING>>
)
STORED AS ORC;

-- STRUCT 嵌套 STRUCT
CREATE TABLE profiles (
    id   BIGINT,
    info STRUCT<
        personal: STRUCT<name: STRING, age: INT>,
        contact:  STRUCT<email: STRING, phone: STRING>
    >
)
STORED AS ORC;

SELECT info.personal.name, info.contact.email FROM profiles;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Hive 原生支持 ARRAY、MAP、STRUCT
-- 2. 支持任意深度的嵌套
-- 3. LATERAL VIEW EXPLODE 是展开数组/Map 的标准方式
-- 4. ARRAY 下标从 0 开始
-- 5. ORC/Parquet 格式对复杂类型有最佳支持
-- 6. COLLECT_LIST/COLLECT_SET 是聚合函数
-- 7. 复杂类型不能作为分区列
