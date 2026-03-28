-- MaxCompute (ODPS): 复合类型 (ARRAY, MAP, STRUCT)
--
-- 参考资料:
--   [1] MaxCompute 文档 - 复杂类型
--       https://help.aliyun.com/zh/maxcompute/user-guide/complex-type-functions
--   [2] MaxCompute 文档 - LATERAL VIEW
--       https://help.aliyun.com/zh/maxcompute/user-guide/lateral-view

-- ============================================================
-- 1. ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     BIGINT,
    name   STRING,
    tags   ARRAY<STRING>,
    scores ARRAY<INT>
);

INSERT INTO users VALUES
    (1, 'Alice', ARRAY('admin', 'dev'), ARRAY(90, 85, 95)),
    (2, 'Bob',   ARRAY('user', 'tester'), ARRAY(70, 80, 75));

-- 数组索引（从 0 开始 — 与 Hive 一致，非 SQL 标准的 1 开始）
SELECT tags[0] FROM users;                  -- 第一个元素
SELECT SIZE(tags) FROM users;               -- 元素数量

-- ARRAY 函数
SELECT ARRAY_CONTAINS(tags, 'admin') FROM users;     -- 包含检查
SELECT SORT_ARRAY(scores) FROM users;                -- 排序
SELECT ARRAY_DISTINCT(tags) FROM users;              -- 去重
SELECT ARRAY_UNION(ARRAY('a','b'), ARRAY('b','c'));   -- 并集
SELECT ARRAY_INTERSECT(ARRAY(1,2,3), ARRAY(2,3,4));  -- 交集
SELECT ARRAY_EXCEPT(ARRAY(1,2,3), ARRAY(2));          -- 差集
SELECT ARRAY_JOIN(tags, ', ') FROM users;            -- 连接为字符串
SELECT ARRAY_POSITION(tags, 'admin') FROM users;     -- 查找位置
SELECT ARRAY_REMOVE(tags, 'admin') FROM users;       -- 移除元素
SELECT CONCAT_WS(',', tags) FROM users;              -- 数组→字符串

-- EXPLODE: 数组展开为多行
SELECT u.name, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- POSEXPLODE: 带位置信息的展开
SELECT u.name, t.pos, t.tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- OUTER EXPLODE: 空数组保留行（生成 NULL）
SELECT u.name, t.tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- 聚合为数组
SELECT COLLECT_LIST(name) FROM users;       -- 收集为数组（含重复）
SELECT COLLECT_SET(name) FROM users;        -- 收集为去重数组

-- ============================================================
-- 2. MAP 类型
-- ============================================================

CREATE TABLE products (
    id         BIGINT,
    name       STRING,
    attributes MAP<STRING, STRING>,
    metrics    MAP<STRING, DOUBLE>
);

INSERT INTO products VALUES
    (1, 'Laptop', MAP('brand', 'Dell', 'ram', '16GB'), MAP('price', 999.99));

-- MAP 访问
SELECT attributes['brand'] FROM products;   -- 键值查找
SELECT MAP_KEYS(attributes) FROM products;  -- 所有键 → ARRAY<STRING>
SELECT MAP_VALUES(attributes) FROM products;-- 所有值 → ARRAY<STRING>
SELECT SIZE(attributes) FROM products;      -- 键值对数量

-- MAP 展开
SELECT p.name, t.key, t.value
FROM products p
LATERAL VIEW EXPLODE(p.attributes) t AS key, value;

-- STR_TO_MAP: 字符串→MAP
SELECT STR_TO_MAP('a:1,b:2,c:3', ',', ':');
-- 结果: {'a':'1', 'b':'2', 'c':'3'}

-- MAP 构造
SELECT MAP('k1', 'v1', 'k2', 'v2');

-- ============================================================
-- 3. STRUCT 类型
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    customer STRUCT<name: STRING, email: STRING>,
    address  STRUCT<city: STRING, zip: STRING>
);

INSERT INTO orders VALUES (
    1,
    NAMED_STRUCT('name', 'Alice', 'email', 'alice@example.com'),
    NAMED_STRUCT('city', 'NYC', 'zip', '10001')
);

-- STRUCT 访问（点号语法）
SELECT customer.name, address.city FROM orders;

-- STRUCT 构造
SELECT NAMED_STRUCT('name', 'alice', 'age', 25);   -- 带字段名
SELECT STRUCT('alice', 25);                         -- 不带字段名

-- ============================================================
-- 4. 嵌套类型
-- ============================================================

-- ARRAY<STRUCT>（最常见的嵌套场景）
CREATE TABLE invoices (
    id    BIGINT,
    items ARRAY<STRUCT<name: STRING, qty: INT, price: DOUBLE>>
);

-- 展开 ARRAY<STRUCT>
SELECT e.id, t.item.name, t.item.qty, t.item.price
FROM invoices e
LATERAL VIEW EXPLODE(e.items) t AS item;

-- MAP<STRING, ARRAY<STRING>>
CREATE TABLE user_prefs (
    user_id BIGINT,
    prefs   MAP<STRING, ARRAY<STRING>>
);

-- 任意深度嵌套都是合法的（但实际使用中不建议超过 3 层）

-- ============================================================
-- 5. 设计分析: Hive 遗产与列式存储的互动
-- ============================================================

-- MaxCompute 的复合类型直接继承自 Hive:
--   ARRAY/MAP/STRUCT 语法与 Hive 完全相同
--   LATERAL VIEW EXPLODE 是 Hive 引入的展开机制
--
-- AliORC 中的复合类型存储:
--   ARRAY: 长度列 + 元素列（元素列按列式存储）
--   MAP:   长度列 + key 列 + value 列
--   STRUCT: 每个字段是独立的子列（完全列式）
--   这意味着: SELECT address.city FROM orders 只读取 city 子列
--             列裁剪不仅在顶层列，也在 STRUCT 字段级别
--
--   对比:
--     Parquet: 同样支持嵌套类型的列式存储（repeated/group）
--     BigQuery: 完全列式的嵌套类型（基于 Dremel 论文）
--     Snowflake: VARIANT 类型用半结构化存储（不是纯列式）

-- ============================================================
-- 6. 复合类型 vs JSON
-- ============================================================

-- 场景: 用户有多个地址
-- JSON 方式:
--   addresses STRING = '[{"city":"NYC","zip":"10001"},{"city":"LA","zip":"90001"}]'
--   查询: GET_JSON_OBJECT(addresses, '$[0].city')
--   每次查询解析 JSON → 慢

-- ARRAY<STRUCT> 方式:
--   addresses ARRAY<STRUCT<city: STRING, zip: STRING>>
--   查询: addresses[0].city
--   列式存储原生读取 → 快，且支持谓词下推

-- 选择指南:
--   schema 固定 → 复合类型（STRUCT/ARRAY/MAP）
--   schema 变化 → JSON 类型（或 STRING 存 JSON）
--   性能优先 → 复合类型
--   灵活性优先 → JSON

-- ============================================================
-- 7. 横向对比: 复合类型
-- ============================================================

-- ARRAY:
--   MaxCompute: ARRAY<T>（Hive 兼容）     | PostgreSQL: T[]（原生数组）
--   BigQuery:   ARRAY<T>                  | Snowflake: ARRAY（VARIANT 元素）
--   MySQL:      不支持原生数组             | ClickHouse: Array(T)

-- MAP:
--   MaxCompute: MAP<K,V>（Hive 兼容）     | BigQuery: 不支持 MAP
--   Snowflake:  不支持 MAP（用 VARIANT）  | ClickHouse: Map(K,V)
--   PostgreSQL: hstore 扩展 / JSONB       | MySQL: 不支持

-- STRUCT:
--   MaxCompute: STRUCT<name: T>（Hive 兼容）
--   BigQuery:   STRUCT<name T>（最常用）
--   Snowflake:  OBJECT（通过 VARIANT）
--   PostgreSQL: 复合类型（CREATE TYPE）
--   ClickHouse: Tuple(name T)

-- 展开语法:
--   MaxCompute: LATERAL VIEW EXPLODE     | Hive: 相同
--   BigQuery:   UNNEST(array)            | PostgreSQL: UNNEST(array)
--   Snowflake:  FLATTEN(array)           | Presto: CROSS JOIN UNNEST

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- 1. 列式存储下复合类型应支持子列裁剪（STRUCT.field 只读一个子列）
-- 2. ARRAY/MAP/STRUCT 是大数据引擎的必备特性（替代行存的 JSON 依赖）
-- 3. LATERAL VIEW 是 Hive 遗产，UNNEST 是更通用的标准 — 新引擎应支持后者
-- 4. 数组下标从 0 开始（Hive/MaxCompute）还是 1 开始（SQL 标准）需要统一
-- 5. COLLECT_LIST/COLLECT_SET 聚合函数是 EXPLODE 的逆操作 — 成对提供
-- 6. 嵌套类型的深度应有上限（防止极深嵌套导致元数据膨胀）
