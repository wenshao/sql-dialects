-- openGauss: 复合/复杂类型 (Array, Map, Struct)
-- PostgreSQL compatible ARRAY, composite types, hstore, and JSONB.
--
-- 参考资料:
--   [1] openGauss 文档 - 数组类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/ARRAY.html
--   [2] openGauss 文档 - 复合类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-TYPE.html
--   [3] openGauss 文档 - JSON/JSONB 类型
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/JSON-JSONB.html
--   [4] PostgreSQL Documentation - Arrays
--       https://www.postgresql.org/docs/current/arrays.html

-- ============================================================
-- 1. ARRAY 类型
-- ============================================================

-- openGauss 继承 PostgreSQL 的原生数组类型
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
    ('Charlie', '{"vip", "premium"}', '{80, 90, 100}');  -- 字符串字面量语法

-- 数组读取
SELECT tags[1] FROM users;                       -- 'admin'（下标从 1 开始!）
SELECT tags[2] FROM users;                       -- 'dev'
SELECT scores[1] FROM users;                     -- 90

-- 数组维度信息
SELECT ARRAY_LENGTH(tags, 1) FROM users;         -- 数组长度（维度 1）
SELECT ARRAY_DIMS(tags) FROM users;              -- '[1:2]'（维度范围）
SELECT ARRAY_NDIMS(tags) FROM users;             -- 维度数（1）

-- ============================================================
-- 2. 数组查询操作符
-- ============================================================

-- 包含: @>（左侧是否包含右侧所有元素）
SELECT * FROM users WHERE tags @> ARRAY['admin'];       -- Alice

-- 被包含: <@
SELECT * FROM users WHERE ARRAY['admin', 'dev'] <@ tags;

-- 重叠: &&（是否有共同元素）
SELECT * FROM users WHERE tags && ARRAY['admin', 'user']; -- Alice, Bob

-- 相等: =
SELECT * FROM users WHERE tags = ARRAY['admin', 'dev'];

-- ANY 操作符: 数组中任一元素满足条件
SELECT * FROM users WHERE 'admin' = ANY(tags);           -- Alice
SELECT * FROM users WHERE 90 = ANY(scores);              -- Alice, Charlie

-- ALL 操作符: 数组中所有元素满足条件
SELECT * FROM users WHERE 80 <= ALL(scores);             -- Alice(90,85,95), Charlie(80,90,100)

-- ============================================================
-- 3. 数组函数
-- ============================================================

-- 展开: UNNEST（数组→行集合）
SELECT UNNEST(tags) FROM users;                  -- 每个元素一行
SELECT UNNEST(scores) FROM users;                -- 每个分数一行

-- 多数组并行展开
SELECT * FROM UNNEST(ARRAY['a','b'], ARRAY[1,2]) AS t(tag, score);
-- tag | score
-- a   | 1
-- b   | 2

-- 聚合: ARRAY_AGG（行→数组）
SELECT department, ARRAY_AGG(name) FROM employees GROUP BY department;

-- 其他常用函数
SELECT ARRAY_APPEND(tags, 'new_tag') FROM users;     -- 追加元素
SELECT ARRAY_PREPEND('first', tags) FROM users;       -- 前置元素
SELECT ARRAY_REMOVE(tags, 'dev') FROM users;          -- 删除元素
SELECT ARRAY_CAT(ARRAY[1,2], ARRAY[3,4]);             -- 连接数组
SELECT ARRAY_POSITION(tags, 'admin') FROM users;      -- 查找元素位置

-- ============================================================
-- 4. 数组索引
-- ============================================================

-- GIN 索引: 支持 @>、<@、&&、= 操作符
CREATE INDEX idx_tags ON users USING gin (tags);

-- 数组上的 GIN 索引适合"包含"查询
-- 例如: WHERE tags @> ARRAY['admin'] 可以利用 GIN 索引

-- ============================================================
-- 5. 复合类型（STRUCT 的替代）
-- ============================================================

-- openGauss 支持 PostgreSQL 风格的复合类型
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

-- 插入复合类型数据
INSERT INTO customers (name, addr) VALUES
    ('Alice', ROW('123 Main St', 'Beijing', '100000')),
    ('Bob',   ('456 Oak Ave', 'Shanghai', '200000'));     -- ROW 可省略

-- 读取复合类型字段
SELECT (addr).city FROM customers;                -- 'Beijing'
SELECT (addr).street FROM customers;              -- '123 Main St'
SELECT (addr).zip FROM customers;                 -- '100000'

-- 更新复合类型字段
UPDATE customers SET addr.city = 'Shenzhen' WHERE id = 1;

-- 复合类型输入/输出格式
-- 输入: ('123 Main St', 'Beijing', '100000')
-- 输出: (123 Main St,Beijing,100000)

-- ============================================================
-- 6. 嵌套数组与多维数组
-- ============================================================

-- 二维数组
CREATE TABLE matrix (
    id   SERIAL PRIMARY KEY,
    data INTEGER[][]                       -- 二维整数数组
);

INSERT INTO matrix (data) VALUES (ARRAY[[1,2,3],[4,5,6]]);
SELECT data[1][2] FROM matrix;                    -- 2（第一行第二列）

-- 数组的数组（非矩形）
-- PostgreSQL 不支持非矩形多维数组，所有行的长度必须一致

-- ============================================================
-- 7. JSONB 作为灵活映射（MAP 的替代）
-- ============================================================

-- 对于 schema-less 的键值对需求，使用 JSONB
CREATE TABLE user_prefs (
    id     SERIAL PRIMARY KEY,
    prefs  JSONB                              -- 替代 MAP<TEXT, TEXT>
);

INSERT INTO user_prefs (prefs) VALUES ('{"theme": "dark", "lang": "zh", "notify": true}');

-- 键值操作
SELECT prefs->>'theme' FROM user_prefs;              -- 'dark'
SELECT prefs ? 'theme' FROM user_prefs;               -- true
SELECT prefs || '{"font": "serif"}' FROM user_prefs;  -- 添加键
SELECT prefs - 'notify' FROM user_prefs;              -- 删除键

-- JSONB 索引
CREATE INDEX idx_prefs ON user_prefs USING gin (prefs);

-- ============================================================
-- 8. openGauss 与 PostgreSQL 复合类型的差异
-- ============================================================

-- 相同点:
--   ARRAY 类型语法和操作符完全兼容
--   复合类型 CREATE TYPE / ROW 语法兼容
--   JSONB 操作符和函数兼容
--   GIN 索引支持数组查询
--
-- 差异点:
--   1. openGauss 额外支持 Oracle 兼容的 VARRAY 类型（Oracle 兼容模式）
--   2. openGauss 的 hstore 扩展可能需要单独安装
--   3. openGauss 的数组操作性能可能因版本而异

-- ============================================================
-- 9. 注意事项与最佳实践
-- ============================================================

-- 1. 数组下标从 1 开始（不是 0!）— 与 C/Java/Python 不同
-- 2. 高频"包含"查询使用 GIN 索引: CREATE INDEX USING gin (array_col)
-- 3. 固定结构用复合类型，灵活结构用 JSONB
-- 4. UNNEST 是最常用的数组→行转换函数
-- 5. ARRAY_AGG 是行→数组的聚合函数
-- 6. 大数组可能触发 TOAST 溢出存储，查询性能需评估
-- 7. 多维数组必须为矩形（所有行长度一致）
-- 8. 复合类型字段访问需要括号: (col).field，避免语法歧义
