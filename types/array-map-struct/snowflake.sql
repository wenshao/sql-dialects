-- Snowflake: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Snowflake Documentation - ARRAY Data Type
--       https://docs.snowflake.com/en/sql-reference/data-types-semistructured#array
--   [2] Snowflake Documentation - OBJECT Data Type
--       https://docs.snowflake.com/en/sql-reference/data-types-semistructured#object
--   [3] Snowflake Documentation - VARIANT Data Type
--       https://docs.snowflake.com/en/sql-reference/data-types-semistructured#variant
--   [4] Snowflake Documentation - Array Functions
--       https://docs.snowflake.com/en/sql-reference/functions-semistructured
--   [5] Snowflake Documentation - MAP Data Type
--       https://docs.snowflake.com/en/sql-reference/data-types-semistructured#map

-- ============================================================
-- 半结构化数据类型概述
-- ============================================================
-- Snowflake 提供三种半结构化类型:
-- VARIANT: 可以存储任意类型（标量、数组、对象）
-- ARRAY: 有序的 VARIANT 元素集合
-- OBJECT: 键值对集合（键为字符串）
-- MAP: 类型化的键值对集合（Snowflake 新增）

-- ============================================================
-- ARRAY 类型
-- ============================================================

CREATE TABLE users (
    id     NUMBER NOT NULL,
    name   VARCHAR(100) NOT NULL,
    tags   ARRAY,                              -- 动态类型 ARRAY
    scores ARRAY
);

-- 插入数组数据
INSERT INTO users SELECT
    1, 'Alice', ARRAY_CONSTRUCT('admin', 'dev'), ARRAY_CONSTRUCT(90, 85, 95);
INSERT INTO users SELECT
    2, 'Bob', ARRAY_CONSTRUCT('user', 'tester'), ARRAY_CONSTRUCT(70, 80, 75);

-- 使用 PARSE_JSON
INSERT INTO users SELECT
    3, 'Carol', PARSE_JSON('["dev", "ops"]'), PARSE_JSON('[88, 92]');

-- 数组索引（从 0 开始）
SELECT tags[0]::VARCHAR FROM users;           -- 第一个元素
SELECT GET(tags, 0) FROM users;               -- 等价

-- ============================================================
-- ARRAY 函数
-- ============================================================

-- ARRAY_SIZE: 长度
SELECT ARRAY_SIZE(tags) FROM users;

-- ARRAY_CONTAINS: 包含检查
SELECT ARRAY_CONTAINS('admin'::VARIANT, tags) FROM users;

-- ARRAY_POSITION: 查找位置（从 0 开始）
SELECT ARRAY_POSITION('admin'::VARIANT, tags) FROM users;

-- ARRAY_APPEND / ARRAY_PREPEND
SELECT ARRAY_APPEND(tags, 'new_tag') FROM users;
SELECT ARRAY_PREPEND(tags, 'first') FROM users;

-- ARRAY_CAT: 连接
SELECT ARRAY_CAT(ARRAY_CONSTRUCT(1,2), ARRAY_CONSTRUCT(3,4));

-- ARRAY_COMPACT: 移除 NULL
SELECT ARRAY_COMPACT(ARRAY_CONSTRUCT(1, NULL, 2, NULL, 3));

-- ARRAY_DISTINCT: 去重
SELECT ARRAY_DISTINCT(ARRAY_CONSTRUCT(1, 2, 2, 3));

-- ARRAY_INTERSECTION: 交集
SELECT ARRAY_INTERSECTION(ARRAY_CONSTRUCT(1,2,3), ARRAY_CONSTRUCT(2,3,4));

-- ARRAY_EXCEPT: 差集（Snowflake 2023+）
SELECT ARRAY_EXCEPT(ARRAY_CONSTRUCT(1,2,3), ARRAY_CONSTRUCT(2));

-- ARRAY_SLICE: 切片
SELECT ARRAY_SLICE(ARRAY_CONSTRUCT(1,2,3,4,5), 1, 3);  -- [2,3]

-- ARRAY_SORT: 排序
SELECT ARRAY_SORT(ARRAY_CONSTRUCT(3, 1, 2));

-- ARRAY_TO_STRING: 转为字符串
SELECT ARRAY_TO_STRING(ARRAY_CONSTRUCT('a','b','c'), ', ');

-- ARRAY_CONSTRUCT_COMPACT: 构造时排除 NULL
SELECT ARRAY_CONSTRUCT_COMPACT(1, NULL, 2, NULL, 3);

-- ============================================================
-- FLATTEN: 展开数组为行（= UNNEST）
-- ============================================================

-- 基本 FLATTEN
SELECT u.name, f.value::VARCHAR AS tag
FROM users u, LATERAL FLATTEN(input => u.tags) f;

-- FLATTEN 参数
-- input: 要展开的 VARIANT/ARRAY/OBJECT
-- path: JSON 路径
-- outer: 是否保留空值行（类似 LEFT JOIN）
-- recursive: 是否递归展开
-- mode: 展开模式 ('BOTH', 'ARRAY', 'OBJECT')

-- OUTER FLATTEN（保留空数组的行）
SELECT u.name, f.value::VARCHAR AS tag
FROM users u, LATERAL FLATTEN(input => u.tags, outer => TRUE) f;

-- FLATTEN 返回的列:
-- SEQ: 序列号
-- KEY: 键（对象）或索引（数组）
-- PATH: JSON 路径
-- INDEX: 数组索引
-- VALUE: 值
-- THIS: 当前正在展开的元素

-- ============================================================
-- ARRAY_AGG: 聚合为数组
-- ============================================================

SELECT department, ARRAY_AGG(name) WITHIN GROUP (ORDER BY name) AS members
FROM employees
GROUP BY department;

-- ARRAY_AGG DISTINCT
SELECT ARRAY_AGG(DISTINCT tag) FROM users, LATERAL FLATTEN(input => tags) f;

-- ============================================================
-- OBJECT 类型（= MAP / STRUCT）
-- ============================================================

CREATE TABLE products (
    id         NUMBER NOT NULL,
    name       VARCHAR(100),
    attributes OBJECT,                         -- 键值对
    metadata   VARIANT                         -- 任意结构
);

-- 插入 OBJECT 数据
INSERT INTO products SELECT
    1, 'Laptop',
    OBJECT_CONSTRUCT('brand', 'Dell', 'ram', '16GB', 'cpu', 'i7'),
    PARSE_JSON('{"category": "electronics", "ratings": [4.5, 4.8]}');

-- 访问 OBJECT 字段
SELECT attributes['brand']::VARCHAR FROM products;
SELECT attributes:brand::VARCHAR FROM products;    -- 冒号语法
SELECT metadata:category::VARCHAR FROM products;

-- 嵌套访问
SELECT metadata:ratings[0]::FLOAT FROM products;

-- OBJECT 函数
SELECT OBJECT_KEYS(attributes) FROM products;      -- 所有键

-- OBJECT_CONSTRUCT: 构造对象
SELECT OBJECT_CONSTRUCT('k1', 'v1', 'k2', 'v2');

-- OBJECT_INSERT: 添加/修改键值对
SELECT OBJECT_INSERT(attributes, 'color', 'black') FROM products;

-- OBJECT_DELETE: 删除键
SELECT OBJECT_DELETE(attributes, 'cpu') FROM products;

-- OBJECT_PICK: 选择指定键
SELECT OBJECT_PICK(attributes, 'brand', 'ram') FROM products;

-- FLATTEN OBJECT
SELECT p.name, f.key, f.value::VARCHAR
FROM products p, LATERAL FLATTEN(input => p.attributes) f;

-- OBJECT_AGG: 聚合为对象（= MAP_AGG）
SELECT OBJECT_AGG(name, salary::VARIANT) FROM employees;

-- ============================================================
-- MAP 类型（Snowflake 结构化类型）
-- ============================================================

-- 结构化 MAP 类型（Snowflake 2023+）
CREATE TABLE configs (
    id       NUMBER,
    settings MAP(VARCHAR, VARCHAR)
);

-- ============================================================
-- 嵌套类型
-- ============================================================

-- ARRAY of OBJECT
INSERT INTO products SELECT 2, 'Bundle',
    OBJECT_CONSTRUCT('type', 'bundle'),
    PARSE_JSON('[
        {"product": "Widget", "qty": 2, "price": 9.99},
        {"product": "Gadget", "qty": 1, "price": 29.99}
    ]');

-- 展开嵌套
SELECT p.name, f.value:product::VARCHAR AS product, f.value:price::FLOAT AS price
FROM products p, LATERAL FLATTEN(input => p.metadata) f
WHERE p.id = 2;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Snowflake 使用 VARIANT/ARRAY/OBJECT 三种半结构化类型
-- 2. ARRAY 索引从 0 开始
-- 3. FLATTEN 是展开数组/对象的主要方式
-- 4. VARIANT 可以存储任意类型数据
-- 5. 半结构化数据支持 Micro-Partition 剪枝
-- 6. 冒号语法 (:) 提供简洁的字段访问
