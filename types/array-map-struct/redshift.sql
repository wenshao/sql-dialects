-- Amazon Redshift: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Redshift Documentation - SUPER Data Type
--       https://docs.aws.amazon.com/redshift/latest/dg/r_SUPER_type.html
--   [2] Redshift Documentation - Querying Semistructured Data
--       https://docs.aws.amazon.com/redshift/latest/dg/query-super.html
--   [3] Redshift Documentation - PartiQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/r_partiql_functions.html

-- ============================================================
-- SUPER 类型（Redshift 的半结构化数据类型）
-- ============================================================
-- Redshift 使用 SUPER 类型存储 JSON/数组/对象
-- 类似 Snowflake 的 VARIANT

CREATE TABLE users (
    id     INTEGER NOT NULL,
    name   VARCHAR(100) NOT NULL,
    tags   SUPER,                             -- 存储数组
    metadata SUPER                            -- 存储对象
);

-- ============================================================
-- ARRAY（通过 SUPER 类型）
-- ============================================================

-- 插入数组
INSERT INTO users VALUES
    (1, 'Alice', JSON_PARSE('["admin", "dev"]'), JSON_PARSE('{"city": "NYC"}')),
    (2, 'Bob',   ARRAY('user', 'tester'), JSON_PARSE('{"city": "LA"}'));

-- 数组索引（从 0 开始）
SELECT tags[0]::VARCHAR FROM users;

-- ARRAY 构造
SELECT ARRAY(1, 2, 3);
SELECT JSON_PARSE('[1, 2, 3]');

-- 数组长度
SELECT GET_ARRAY_LENGTH(tags) FROM users;

-- ============================================================
-- UNNEST: 展开数组为行
-- ============================================================

-- PartiQL 语法展开
SELECT u.name, t AS tag
FROM users u, u.tags AS t;

-- 使用 UNPIVOT 等效
SELECT u.name, tag.value::VARCHAR AS tag
FROM users u, SUPER_UNNEST(u.tags) AS tag(value);

-- ============================================================
-- OBJECT（通过 SUPER 类型）
-- ============================================================

-- 访问对象字段
SELECT metadata.city::VARCHAR FROM users;

-- 嵌套访问
UPDATE users SET metadata = JSON_PARSE('{
    "city": "NYC",
    "settings": {"theme": "dark"},
    "phones": ["+1-555-0100", "+1-555-0200"]
}') WHERE id = 1;

SELECT metadata.settings.theme::VARCHAR FROM users WHERE id = 1;
SELECT metadata.phones[0]::VARCHAR FROM users WHERE id = 1;

-- ============================================================
-- OBJECT 构造
-- ============================================================

SELECT JSON_PARSE('{"key": "value"}');

-- ============================================================
-- 聚合函数
-- ============================================================

-- LISTAGG（字符串聚合，非数组）
SELECT department, LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name)
FROM employees
GROUP BY department;

-- ============================================================
-- 嵌套类型
-- ============================================================

-- SUPER 支持任意嵌套
INSERT INTO users (id, name, tags, metadata) VALUES (3, 'Carol', JSON_PARSE('[
    {"role": "dev", "level": "senior"},
    {"role": "ops", "level": "mid"}
]'), JSON_PARSE('{}'));

-- 查询嵌套
SELECT u.name, t.role::VARCHAR, t.level::VARCHAR
FROM users u, u.tags AS t
WHERE u.id = 3;

-- ============================================================
-- 类型检查与转换
-- ============================================================

-- JSON_TYPEOF: 检查类型
SELECT JSON_TYPEOF(tags) FROM users;           -- 'array'
SELECT JSON_TYPEOF(metadata) FROM users;       -- 'object'

-- CAST
SELECT tags[0]::VARCHAR FROM users;
SELECT metadata.city::VARCHAR FROM users;

-- IS_ARRAY / IS_OBJECT / IS_SCALAR
SELECT IS_ARRAY(tags), IS_OBJECT(metadata) FROM users;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Redshift 使用 SUPER 类型存储半结构化数据
-- 2. 没有独立的 ARRAY / MAP / STRUCT 关键字
-- 3. PartiQL 语法用于查询 SUPER 数据
-- 4. 数组下标从 0 开始
-- 5. SUPER 列最大 16MB
-- 6. 支持 JSON_PARSE 和 ARRAY() 构造
