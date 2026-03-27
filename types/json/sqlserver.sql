-- SQL Server: JSON 支持（2016+）
--
-- 参考资料:
--   [1] SQL Server - JSON Data
--       https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server

-- ============================================================
-- 1. 核心设计: 没有原生 JSON 类型
-- ============================================================

-- SQL Server 选择不引入 JSON 数据类型——JSON 存储在 NVARCHAR(MAX) 中。
CREATE TABLE events (
    id   BIGINT IDENTITY(1,1) PRIMARY KEY,
    data NVARCHAR(MAX)
);
ALTER TABLE events ADD CONSTRAINT chk_json CHECK (ISJSON(data) = 1);

-- 设计分析（对引擎开发者）:
--   SQL Server 的"无类型 JSON"设计是一个重要的架构决策:
--   优点: 无需新类型，现有索引/函数/工具都能工作
--         NVARCHAR(MAX) 支持所有字符串操作（LIKE, =, 比较）
--   缺点: 无二进制 JSON 格式（每次查询都需要解析 JSON 文本）
--         无法在存储层优化 JSON 访问路径
--
-- 横向对比:
--   PostgreSQL: json（文本）+ jsonb（二进制, 推荐）——jsonb 支持索引和高效访问
--   MySQL:      JSON 类型（内部使用二进制格式）
--   Oracle:     21c+ JSON 类型（之前存在 VARCHAR2/CLOB 中）
--
-- 对引擎开发者的启示:
--   二进制 JSON 格式（如 PostgreSQL 的 jsonb）是性能关键。
--   文本 JSON 的每次字段访问都需要解析整个文档——O(n) 复杂度。
--   二进制格式可以实现 O(1) 字段访问。SQL Server 缺少这个是性能弱点。

-- ============================================================
-- 2. JSON_VALUE / JSON_QUERY: 读取 JSON
-- ============================================================

INSERT INTO events (data) VALUES
('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');

SELECT JSON_VALUE(data, '$.name')  FROM events;  -- 'alice'（标量值）
SELECT JSON_QUERY(data, '$.tags')  FROM events;  -- '["vip","new"]'（对象/数组）
SELECT JSON_VALUE(data, '$.tags[0]') FROM events; -- 'vip'

-- JSON_VALUE vs JSON_QUERY:
--   JSON_VALUE: 返回标量值（字符串/数字/布尔），最大 4000 字符
--   JSON_QUERY: 返回对象或数组（JSON 片段）
--   这个分离是 SQL Server 独有的——其他数据库通常用一个函数处理两种情况

-- ============================================================
-- 3. JSON_MODIFY: 修改 JSON（2016+）
-- ============================================================

SELECT JSON_MODIFY(data, '$.age', 26) FROM events;           -- 修改值
SELECT JSON_MODIFY(data, '$.email', 'a@e.com') FROM events;  -- 添加键
SELECT JSON_MODIFY(data, '$.tags', NULL) FROM events;         -- 删除键
SELECT JSON_MODIFY(data, 'append $.tags', 'hot') FROM events; -- 数组追加

-- 嵌套修改:
UPDATE events SET data = JSON_MODIFY(
    JSON_MODIFY(data, '$.age', 26),
    '$.email', 'alice@example.com'
) WHERE JSON_VALUE(data, '$.name') = 'alice';

-- ============================================================
-- 4. OPENJSON: JSON 展开为关系行
-- ============================================================

-- 默认模式（返回 key, value, type）
SELECT * FROM OPENJSON('{"name":"alice","age":25}');

-- 强类型模式（WITH 子句指定列和类型）
SELECT * FROM OPENJSON('{"name":"alice","age":25}')
WITH (name NVARCHAR(50) '$.name', age INT '$.age');

-- 展开 JSON 数组
SELECT value FROM OPENJSON('["vip","new","hot"]');

-- CROSS APPLY + OPENJSON: 关联展开（核心用法）
SELECT e.id, j.name, j.age
FROM events e
CROSS APPLY OPENJSON(e.data) WITH (
    name NVARCHAR(50) '$.name',
    age  INT          '$.age'
) j;

-- 设计分析:
--   OPENJSON 是 SQL Server 的 JSON_TABLE 等价（SQL:2016 标准定义了 JSON_TABLE）。
--   OPENJSON + CROSS APPLY 的组合是 SQL Server JSON 查询的核心模式。
--
-- 横向对比:
--   PostgreSQL: jsonb_to_record(), jsonb_array_elements()
--   MySQL:      JSON_TABLE()（8.0+, SQL 标准语法）
--   Oracle:     JSON_TABLE()（12c+）

-- ============================================================
-- 5. FOR JSON: 关系数据转 JSON
-- ============================================================

SELECT username, age FROM users FOR JSON PATH;
-- [{"username":"alice","age":25},{"username":"bob","age":30}]

SELECT username FROM users FOR JSON PATH, ROOT('users');
-- {"users":[{"username":"alice"},{"username":"bob"}]}

-- FOR JSON AUTO（自动嵌套 JOIN 结果）
SELECT d.dept_name, e.name FROM departments d
JOIN employees e ON d.id = e.dept_id
FOR JSON AUTO;

-- ============================================================
-- 6. JSON 索引（计算列 + 索引）
-- ============================================================

-- SQL Server 通过计算列实现 JSON 路径的索引:
ALTER TABLE events ADD name AS JSON_VALUE(data, '$.name');
CREATE INDEX ix_name ON events (name);

-- 这是 SQL Server JSON 索引的唯一方式——其他数据库更灵活:
-- PostgreSQL: CREATE INDEX ON t USING GIN (data jsonb_path_ops)（直接在 jsonb 列上）
-- MySQL:      CREATE INDEX ON t ((CAST(data->>'$.name' AS CHAR(50))))（函数索引）
--
-- 对引擎开发者的启示:
--   PostgreSQL 的 GIN 索引可以索引整个 JSON 文档的所有路径——
--   这使得任意路径的查询都能使用索引，无需预先定义。
--   SQL Server 的计算列方案要求 DBA 预知哪些路径需要索引。

-- ============================================================
-- 7. 2022+: JSON_OBJECT / JSON_ARRAY 构造函数
-- ============================================================

SELECT JSON_OBJECT('name': username, 'age': age) FROM users;
SELECT JSON_ARRAY(username, email) FROM users;

-- ISJSON 验证
SELECT ISJSON('{"a":1}');  -- 1
SELECT ISJSON('invalid');  -- 0

-- 版本演进:
-- 2016  : JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON, FOR JSON, ISJSON
-- 2022  : JSON_OBJECT, JSON_ARRAY
-- 未来  : JSON_TABLE（SQL 标准语法, 预览中）
-- 缺失: 无原生 JSON 类型, 无二进制 JSON, 无 GIN 索引
