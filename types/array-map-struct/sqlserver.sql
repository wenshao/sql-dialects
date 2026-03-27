-- SQL Server: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Microsoft Docs - JSON Data in SQL Server
--       https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server
--   [2] Microsoft Docs - OPENJSON
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql
--   [3] Microsoft Docs - JSON_ARRAY / JSON_OBJECT (SQL Server 2022)
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/json-array-transact-sql
--   [4] Microsoft Docs - Table-Valued Parameters
--       https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine

-- ============================================================
-- SQL Server 没有原生的 ARRAY / MAP / STRUCT 类型
-- 使用 JSON 或 XML 作为替代
-- ============================================================

-- ============================================================
-- JSON 数组（代替 ARRAY）— SQL Server 2016+
-- ============================================================

CREATE TABLE users (
    id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    name     NVARCHAR(100) NOT NULL,
    tags     NVARCHAR(MAX),                   -- 存储 JSON 数组
    metadata NVARCHAR(MAX),                   -- 存储 JSON 对象
    CONSTRAINT chk_tags CHECK (ISJSON(tags) = 1),
    CONSTRAINT chk_meta CHECK (ISJSON(metadata) = 1)
);

-- 插入 JSON 数组
INSERT INTO users (name, tags) VALUES
    ('Alice', '["admin", "dev"]'),
    ('Bob',   '["user", "tester"]');

-- JSON_ARRAY 构造函数（SQL Server 2022+）
INSERT INTO users (name, tags) VALUES
    ('Carol', JSON_ARRAY('dev', 'ops'));

-- 访问 JSON 数组元素
SELECT JSON_VALUE(tags, '$[0]') AS first_tag FROM users;    -- 标量值
SELECT JSON_QUERY(tags, '$[0]') AS first_elem FROM users;   -- JSON 片段

-- ============================================================
-- OPENJSON: 展开 JSON 数组为行（= UNNEST）
-- ============================================================

-- 展开 JSON 数组
SELECT u.name, j.value AS tag
FROM users u
CROSS APPLY OPENJSON(u.tags) j;

-- 带类型的展开
SELECT u.name, j.value AS tag, j.[key] AS idx
FROM users u
CROSS APPLY OPENJSON(u.tags) j;

-- 展开为强类型列
SELECT u.name, j.tag
FROM users u
CROSS APPLY OPENJSON(u.tags) WITH (
    tag NVARCHAR(50) '$'
) j;

-- ============================================================
-- JSON 对象（代替 MAP / STRUCT）
-- ============================================================

-- JSON_OBJECT 构造（SQL Server 2022+）
UPDATE users
SET metadata = JSON_OBJECT('city': 'New York', 'country': 'US',
                           'settings': JSON_OBJECT('theme': 'dark'))
WHERE id = 1;

-- 字面量
UPDATE users
SET metadata = '{"city": "Boston", "country": "US"}'
WHERE id = 2;

-- 访问字段
SELECT JSON_VALUE(metadata, '$.city') FROM users;
SELECT JSON_VALUE(metadata, '$.settings.theme') FROM users;

-- JSON_MODIFY: 修改 JSON（SQL Server 2016+）
UPDATE users
SET metadata = JSON_MODIFY(metadata, '$.zip', '10001')
WHERE id = 1;

-- 删除键
UPDATE users
SET metadata = JSON_MODIFY(metadata, '$.city', NULL)
WHERE id = 1;

-- ============================================================
-- OPENJSON 展开对象
-- ============================================================

-- 展开 JSON 对象为键值对
SELECT u.name, j.[key], j.value, j.type
FROM users u
CROSS APPLY OPENJSON(u.metadata) j;
-- type: 0=null, 1=string, 2=number, 3=boolean, 4=array, 5=object

-- 展开为强类型列
SELECT *
FROM OPENJSON('{"name":"Alice","age":30,"city":"NYC"}')
WITH (
    name NVARCHAR(50) '$.name',
    age  INT          '$.age',
    city NVARCHAR(50) '$.city'
);

-- ============================================================
-- 聚合为 JSON — FOR JSON
-- ============================================================

-- FOR JSON PATH: 将结果集转为 JSON 数组
SELECT name, salary
FROM employees
FOR JSON PATH;
-- [{"name":"Alice","salary":50000},{"name":"Bob","salary":60000}]

-- FOR JSON AUTO
SELECT d.dept_name, e.name
FROM departments d
JOIN employees e ON d.id = e.dept_id
FOR JSON AUTO;

-- STRING_AGG 模拟 ARRAY_AGG
SELECT department, STRING_AGG(name, ', ') AS members
FROM employees
GROUP BY department;

-- JSON_ARRAYAGG (SQL Server 2022+)
-- 注意：截至 SQL Server 2022 未直接提供，可用 FOR JSON PATH 替代

-- ============================================================
-- 嵌套 JSON
-- ============================================================

DECLARE @json NVARCHAR(MAX) = '{
    "users": [
        {"name": "Alice", "roles": ["admin", "dev"]},
        {"name": "Bob", "roles": ["user"]}
    ],
    "settings": {"theme": "dark"}
}';

-- 多层 OPENJSON
SELECT u.name, r.value AS role
FROM OPENJSON(@json, '$.users') WITH (
    name  NVARCHAR(50) '$.name',
    roles NVARCHAR(MAX) '$.roles' AS JSON
) u
CROSS APPLY OPENJSON(u.roles) r;

-- ============================================================
-- XML 替代方案
-- ============================================================

-- SQL Server 原生支持 XML 类型
DECLARE @xml XML = '<tags><tag>admin</tag><tag>dev</tag></tags>';

-- 查询 XML
SELECT t.c.value('.', 'NVARCHAR(50)') AS tag
FROM @xml.nodes('/tags/tag') AS t(c);

-- ============================================================
-- 用户定义表类型（Table-Valued Parameters）
-- ============================================================

-- 创建表类型（用于传递数组到存储过程）
CREATE TYPE StringArray AS TABLE (value NVARCHAR(100));
CREATE TYPE IntArray AS TABLE (value INT);

-- 在存储过程中使用
CREATE PROCEDURE GetUsersByTags
    @tags StringArray READONLY
AS
BEGIN
    SELECT u.*
    FROM users u
    CROSS APPLY OPENJSON(u.tags) j
    WHERE j.value IN (SELECT value FROM @tags);
END;

-- ============================================================
-- JSON 索引（计算列 + 索引）
-- ============================================================

-- 在 JSON 路径上创建索引
ALTER TABLE users ADD city AS JSON_VALUE(metadata, '$.city');
CREATE INDEX idx_city ON users (city);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. SQL Server 没有原生 ARRAY / MAP / STRUCT 类型
-- 2. 使用 NVARCHAR(MAX) + JSON 约束存储 JSON
-- 3. OPENJSON (2016+) 提供 UNNEST 功能
-- 4. JSON_ARRAY/JSON_OBJECT (2022+) 简化 JSON 构造
-- 5. 可以在 JSON 路径上创建计算列索引
-- 6. XML 类型是更早的原生复杂类型支持
