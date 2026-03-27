-- SQL Server: 复合类型（Array / Map / Struct 替代方案）
--
-- 参考资料:
--   [1] SQL Server - JSON Data
--       https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server
--   [2] SQL Server - Table-Valued Parameters
--       https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine

-- ============================================================
-- 1. SQL Server 没有原生 ARRAY / MAP / STRUCT 类型
-- ============================================================

-- SQL Server 使用以下替代方案:
--   ARRAY  → JSON 数组 (NVARCHAR(MAX)) 或 表值参数 (TVP)
--   MAP    → JSON 对象
--   STRUCT → JSON 对象 或 用户定义表类型

-- 横向对比:
--   PostgreSQL: ARRAY[], JSON/JSONB, 复合类型（真正的原生支持）
--   MySQL:      JSON（5.7+）
--   ClickHouse: Array(T), Map(K,V), Tuple(T1,T2,...), Nested
--   BigQuery:   ARRAY, STRUCT, JSON
--
-- 对引擎开发者的启示:
--   原生复合类型（如 PostgreSQL 的 ARRAY）比 JSON 模拟更高效:
--   (1) 类型检查在插入时完成（不是查询时）
--   (2) 存储更紧凑（无 JSON 语法开销）
--   (3) 索引支持更好（GIN 索引直接支持 ARRAY 包含查询）
--   SQL Server 选择"用 JSON 模拟一切"简化了实现但牺牲了性能。

-- ============================================================
-- 2. JSON 数组代替 ARRAY（2016+）
-- ============================================================

CREATE TABLE users (
    id       BIGINT IDENTITY(1,1) PRIMARY KEY,
    name     NVARCHAR(100) NOT NULL,
    tags     NVARCHAR(MAX),
    CONSTRAINT chk_tags CHECK (ISJSON(tags) = 1)
);

INSERT INTO users (name, tags) VALUES
    ('Alice', '["admin", "dev"]'),
    ('Bob',   '["user", "tester"]');

-- 2022+: JSON_ARRAY 构造函数
INSERT INTO users (name, tags) VALUES ('Carol', JSON_ARRAY('dev', 'ops'));

-- 访问元素
SELECT JSON_VALUE(tags, '$[0]') AS first_tag FROM users;

-- OPENJSON 展开数组为行（= PostgreSQL 的 unnest()）
SELECT u.name, j.value AS tag
FROM users u CROSS APPLY OPENJSON(u.tags) j;

-- 带类型信息的展开
SELECT u.name, j.value AS tag, j.[key] AS idx
FROM users u CROSS APPLY OPENJSON(u.tags) j;

-- ============================================================
-- 3. JSON 对象代替 MAP / STRUCT
-- ============================================================

-- 2022+: JSON_OBJECT
UPDATE users SET tags = JSON_OBJECT('city': 'NYC', 'country': 'US') WHERE id = 1;

-- 读取
SELECT JSON_VALUE(tags, '$.city') FROM users;

-- 展开为键值对
SELECT u.name, j.[key], j.value FROM users u CROSS APPLY OPENJSON(u.tags) j;

-- 展开为强类型列
SELECT * FROM OPENJSON('{"name":"Alice","age":30}')
WITH (name NVARCHAR(50) '$.name', age INT '$.age');

-- ============================================================
-- 4. 表值参数 (TVP): 传递数组到存储过程
-- ============================================================

-- 创建用户定义表类型（类似声明一个"数组类型"）
CREATE TYPE dbo.IntArray AS TABLE (value INT NOT NULL);
CREATE TYPE dbo.StringArray AS TABLE (value NVARCHAR(100));

-- 在存储过程中使用
CREATE PROCEDURE GetUsersByIds
    @ids dbo.IntArray READONLY  -- 必须是 READONLY
AS
BEGIN
    SELECT u.* FROM users u
    INNER JOIN @ids i ON u.id = i.value;
END;

-- 调用
DECLARE @my_ids dbo.IntArray;
INSERT INTO @my_ids VALUES (1), (2), (3);
EXEC GetUsersByIds @ids = @my_ids;

-- 设计分析（对引擎开发者）:
--   TVP 是 SQL Server 向存储过程传递"表数据"的唯一方式。
--   它解决了一个经典问题: 如何将 IN 列表作为参数传递。
--   其他方案: 拼接逗号分隔字符串 + STRING_SPLIT（易出错）
--            或 XML/JSON（性能差）
--
-- 横向对比:
--   PostgreSQL: 直接传递 ARRAY 类型（ANYARRAY 参数）
--   Oracle:     嵌套表类型（TABLE OF type）
--   MySQL:      不支持（只能用临时表或 JSON）

-- ============================================================
-- 5. FOR JSON: 关系数据聚合为 JSON
-- ============================================================

SELECT name, salary FROM employees FOR JSON PATH;

-- STRING_AGG 模拟 ARRAY_AGG
SELECT department, STRING_AGG(name, ', ') AS members
FROM employees GROUP BY department;

-- ============================================================
-- 6. 嵌套 JSON 处理
-- ============================================================

DECLARE @json NVARCHAR(MAX) = N'{
    "users": [
        {"name": "Alice", "roles": ["admin", "dev"]},
        {"name": "Bob", "roles": ["user"]}
    ]
}';

-- 多层 OPENJSON
SELECT u.name, r.value AS role
FROM OPENJSON(@json, '$.users') WITH (
    name  NVARCHAR(50) '$.name',
    roles NVARCHAR(MAX) '$.roles' AS JSON
) u
CROSS APPLY OPENJSON(u.roles) r;

-- ============================================================
-- 7. XML 替代方案（SQL Server 原生支持 XML 类型）
-- ============================================================

-- XML 类型是 SQL Server 2005 引入的原生复杂类型（早于 JSON 支持）
DECLARE @xml XML = '<tags><tag>admin</tag><tag>dev</tag></tags>';
SELECT t.c.value('.', 'NVARCHAR(50)') AS tag
FROM @xml.nodes('/tags/tag') AS t(c);

-- XML vs JSON:
--   XML: 原生类型, 支持 XQuery/XPath, 支持 XML Schema 验证, 支持 XML 索引
--   JSON: 文本存储, 更轻量, 2016+ 才支持
--   现代开发更倾向 JSON（更简洁，与 API/前端一致）

-- ============================================================
-- 8. JSON 路径索引（计算列方案）
-- ============================================================

ALTER TABLE users ADD city AS JSON_VALUE(tags, '$.city');
CREATE INDEX ix_city ON users (city);

-- 版本演进:
-- 2005  : XML 类型（原生支持, XQuery）
-- 2008  : 表值参数 (TVP)
-- 2016  : JSON_VALUE, JSON_QUERY, JSON_MODIFY, OPENJSON
-- 2022  : JSON_OBJECT, JSON_ARRAY
-- 缺失: 无原生 ARRAY/MAP/STRUCT, 无 jsonb 等价, 无 JSON_ARRAYAGG
