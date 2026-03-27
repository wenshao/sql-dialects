-- 人大金仓 (KingbaseES): 复合/复杂类型 (Array, Map, Struct)
-- PostgreSQL compatible ARRAY, composite types, hstore, and JSONB.
--
-- 参考资料:
--   [1] KingbaseES 文档 - 数据类型
--       https://help.kingbase.com.cn/v8/development/sql-plsql/sql/SQL_data_types.html
--   [2] KingbaseES 文档 - 数组
--       https://help.kingbase.com.cn/v8/development/sql-plsql/sql/SQL_data_types_8.html
--   [3] KingbaseES Oracle Compatibility Guide
--       https://help.kingbase.com.cn/v8/development/sql-plsql/oracle-compat.html
--   [4] PostgreSQL Documentation - Arrays
--       https://www.postgresql.org/docs/current/arrays.html

-- ============================================================
-- 1. ARRAY 类型
-- ============================================================

-- KingbaseES 继承 PostgreSQL 的原生数组类型
-- 任何内置类型都可以创建数组: INT[], TEXT[], VARCHAR(64)[], JSONB[] 等
CREATE TABLE users (
    id     SERIAL PRIMARY KEY,
    name   TEXT NOT NULL,
    tags   TEXT[],                               -- 文本数组
    scores INTEGER[]                             -- 整数数组
);

-- 插入数组
INSERT INTO users (name, tags, scores) VALUES
    ('Alice', ARRAY['admin', 'dev'], ARRAY[90, 85, 95]),
    ('Bob',   ARRAY['user'], ARRAY[70]),
    ('Charlie', '{user,tester}', '{70,80}');      -- 字符串字面量语法

-- 数组读取（下标从 1 开始）
SELECT tags[1] FROM users;                       -- 'admin'
SELECT tags[2] FROM users;                       -- 'dev'
SELECT scores[1] FROM users;                     -- 90

-- 越界访问返回 NULL（不报错）
SELECT tags[10] FROM users;                      -- NULL

-- 数组维度信息
SELECT ARRAY_LENGTH(tags, 1) FROM users;         -- 数组长度
SELECT ARRAY_DIMS(tags) FROM users;              -- 维度范围 '[1:2]'
SELECT ARRAY_NDIMS(tags) FROM users;             -- 维度数

-- ============================================================
-- 2. 数组查询操作符
-- ============================================================

-- 包含: @>（左侧是否包含右侧所有元素）
SELECT * FROM users WHERE tags @> ARRAY['admin'];       -- Alice

-- 被包含: <@
SELECT * FROM users WHERE ARRAY['admin', 'dev'] <@ tags; -- Alice

-- 重叠: &&（是否有共同元素）
SELECT * FROM users WHERE tags && ARRAY['admin', 'user']; -- Alice, Bob

-- ANY 操作符: 数组中任一元素满足条件
SELECT * FROM users WHERE 'admin' = ANY(tags);            -- Alice
SELECT * FROM users WHERE 80 = ANY(scores);               -- Alice(85,90,95), Bob(70,...不对)

-- ALL 操作符: 数组中所有元素满足条件
SELECT * FROM users WHERE 80 <= ALL(scores);              -- Alice, Charlie

-- ============================================================
-- 3. 数组函数
-- ============================================================

-- UNNEST: 展开（数组→行集合）
SELECT UNNEST(tags) FROM users;                  -- 每个元素一行

-- 多数组并行展开
SELECT * FROM UNNEST(ARRAY['a','b'], ARRAY[1,2]) AS t(tag, score);

-- ARRAY_AGG: 聚合（行→数组）
SELECT department, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY department;

-- 常用数组函数
SELECT ARRAY_APPEND(tags, 'new_tag') FROM users;     -- 追加元素
SELECT ARRAY_PREPEND('first', tags) FROM users;       -- 前置元素
SELECT ARRAY_REMOVE(tags, 'dev') FROM users;          -- 删除指定元素
SELECT ARRAY_CAT(ARRAY[1,2], ARRAY[3,4]);             -- 连接两个数组
SELECT ARRAY_POSITION(tags, 'admin') FROM users;      -- 查找元素位置（从 1 开始）
SELECT ARRAY_REPLACE(scores, 70, 75) FROM users;      -- 替换元素
SELECT CARDINALITY(tags) FROM users;                   -- 元素总数（等同 ARRAY_LENGTH）

-- 字符串与数组互转
SELECT STRING_TO_ARRAY('a,b,c', ',');                 -- {a,b,c}
SELECT ARRAY_TO_STRING(ARRAY['a','b','c'], ',');       -- 'a,b,c'

-- ============================================================
-- 4. 数组索引
-- ============================================================

-- GIN 索引: 支持 @>、<@、&& 操作符（最常用的数组索引）
CREATE INDEX idx_tags ON users USING gin (tags);

-- GIN 索引适合"包含"查询
-- WHERE tags @> ARRAY['admin'] 可以利用 GIN 索引快速定位

-- 表达式索引: 对数组长度等计算建索引
CREATE INDEX idx_tag_count ON users (ARRAY_LENGTH(tags, 1));

-- ============================================================
-- 5. 复合类型（STRUCT 的替代）
-- ============================================================

-- 定义复合类型
CREATE TYPE address AS (
    street TEXT,
    city   TEXT,
    zip    VARCHAR(10)
);

-- 在表中使用复合类型
CREATE TABLE customers (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    addr    address
);

-- 插入复合类型
INSERT INTO customers (name, addr) VALUES
    ('Alice', ROW('123 Main St', 'Beijing', '100000')),
    ('Bob',   ('456 Oak Ave', 'Shanghai', '200000'));

-- 读取复合类型字段（注意括号!）
SELECT (addr).city FROM customers;                -- 'Beijing'
SELECT (addr).street FROM customers;              -- '123 Main St'

-- 更新复合类型的单个字段
UPDATE customers SET addr.city = 'Shenzhen' WHERE id = 1;

-- 复合类型作为函数参数/返回值
CREATE FUNCTION get_full_address(addr address) RETURNS TEXT AS $$
    SELECT addr.street || ', ' || addr.city || ' ' || addr.zip;
$$ LANGUAGE SQL;

SELECT get_full_address(addr) FROM customers;

-- ============================================================
-- 6. hstore: 键值对扩展
-- ============================================================

-- hstore 是 PostgreSQL 的键值对扩展，KingbaseES 兼容
-- 键值都是 TEXT 类型，适合简单映射场景
CREATE EXTENSION IF NOT EXISTS hstore;

CREATE TABLE user_attrs (
    id    SERIAL PRIMARY KEY,
    attrs HSTORE                               -- 键值对映射
);

INSERT INTO user_attrs (attrs) VALUES ('theme => dark, lang => zh');
INSERT INTO user_attrs (attrs) VALUES ('theme => light, notify => true');

-- 读取值
SELECT attrs -> 'theme' FROM user_attrs;         -- 'dark'

-- 键存在
SELECT * FROM user_attrs WHERE attrs ? 'theme';

-- 包含
SELECT * FROM user_attrs WHERE attrs @> 'theme => dark';

-- 添加/更新键
SELECT attrs || 'font => serif' FROM user_attrs;

-- 删除键
SELECT attrs - 'theme' FROM user_attrs;

-- hstore vs JSONB:
--   hstore: 键值都是 TEXT，更轻量，适合简单映射
--   JSONB:  支持嵌套结构、数组、类型区分，功能更强
--   建议: 新项目使用 JSONB，简单映射可用 hstore

-- ============================================================
-- 7. JSONB: 灵活的嵌套结构
-- ============================================================

CREATE TABLE events (
    id   SERIAL PRIMARY KEY,
    data JSONB
);

INSERT INTO events (data) VALUES ('{"tags": ["a", "b"], "meta": {"key": "val"}}');

-- 读取
SELECT data->'tags' FROM events;                       -- JSONB 数组
SELECT data->>'tags' FROM events;                       -- TEXT
SELECT data->'meta'->>'key' FROM events;                -- 嵌套访问

-- 展开 JSONB 数组（等价于 UNNEST 对原生数组的作用）
SELECT jsonb_array_elements_text(data->'tags') FROM events;

-- GIN 索引
CREATE INDEX idx_data ON events USING gin (data);

-- ============================================================
-- 8. Oracle 兼容模式: VARRAY 和嵌套表
-- ============================================================

-- KingbaseES 在 Oracle 兼容模式下支持 Oracle 的集合类型:
-- VARRAY: 定长数组（类似 ARRAY，但有最大长度限制）
-- Nested Table: 嵌套表（变长集合）

-- Oracle 兼容示例（需启用 Oracle 兼容模式）:
-- CREATE TYPE tag_list AS VARRAY(10) OF VARCHAR2(64);
-- CREATE TYPE number_list AS TABLE OF NUMBER;

-- ============================================================
-- 9. 横向对比: 复合类型支持
-- ============================================================

-- ARRAY:
--   KingbaseES:  原生 ARRAY，GIN 索引，UNNEST，ARRAY_AGG
--   PostgreSQL:  原生 ARRAY，完全相同
--   Oracle:      VARRAY / Nested Table
--   MySQL:       无原生 ARRAY，用 JSON 数组替代
--   TDSQL:       无原生 ARRAY，用 JSON 数组替代
--   ClickHouse:  原生 Array，高效向量化
--
-- STRUCT/COMPOSITE:
--   KingbaseES:  CREATE TYPE ... AS (...), ROW(...)
--   PostgreSQL:  CREATE TYPE ... AS (...), ROW(...)
--   Oracle:      OBJECT TYPE
--   MySQL:       无原生 STRUCT，用 JSON 对象替代
--   ClickHouse:  Tuple
--   BigQuery:    STRUCT
--
-- MAP:
--   KingbaseES:  hstore / JSONB
--   PostgreSQL:  hstore / JSONB
--   ClickHouse:  Map
--   BigQuery:    无原生 MAP

-- ============================================================
-- 10. 注意事项与最佳实践
-- ============================================================

-- 1. 数组下标从 1 开始（非 0），越界返回 NULL
-- 2. 高频"包含"查询使用 GIN 索引: CREATE INDEX USING gin (array_col)
-- 3. 固定结构用复合类型，灵活结构用 JSONB
-- 4. UNNEST 是数组→行转换的核心函数
-- 5. ARRAY_AGG 是行→数组的聚合函数
-- 6. hstore 适合简单键值对，JSONB 适合嵌套结构
-- 7. Oracle 兼容模式支持 VARRAY / Nested Table
-- 8. 复合类型字段访问需要括号: (col).field
-- 9. 大数组可能触发 TOAST 溢出，性能需评估
-- 10. STRING_TO_ARRAY / ARRAY_TO_STRING 是字符串与数组互转的常用函数
