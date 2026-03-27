-- SQL Server: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Microsoft Docs - STRING_SPLIT
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/string-split-transact-sql
--   [2] Microsoft Docs - OPENJSON
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql
--   [3] Microsoft Docs - XML Methods
--       https://learn.microsoft.com/en-us/sql/t-sql/xml/nodes-method-xml-data-type

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(100),
    tags NVARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    (N'Alice', N'python,java,sql'),
    (N'Bob',   N'go,rust'),
    (N'Carol', N'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: STRING_SPLIT（推荐, SQL Server 2016+）
-- ============================================================
SELECT t.id, t.name, s.value AS tag
FROM   tags_csv t
CROSS APPLY STRING_SPLIT(t.tags, ',') s;

-- STRING_SPLIT 带序号（SQL Server 2022+ / Azure SQL）
SELECT t.id, t.name, s.value AS tag, s.ordinal
FROM   tags_csv t
CROSS APPLY STRING_SPLIT(t.tags, ',', 1) s
ORDER BY t.id, s.ordinal;

-- ============================================================
-- 方法 2: OPENJSON（SQL Server 2016+，保留顺序）
-- ============================================================
SELECT t.id, t.name, j.[value] AS tag, j.[key] AS pos
FROM   tags_csv t
CROSS APPLY OPENJSON('["' + REPLACE(t.tags, ',', '","') + '"]') j;

-- ============================================================
-- 方法 3: XML 方法（SQL Server 2005+）
-- ============================================================
SELECT t.id, t.name,
       x.node.value('.', 'NVARCHAR(100)') AS tag
FROM   tags_csv t
CROSS APPLY (
    SELECT CAST('<x>' + REPLACE(t.tags, ',', '</x><x>') + '</x>' AS XML) AS xml_data
) AS parsed
CROSS APPLY parsed.xml_data.nodes('/x') AS x(node);

-- ============================================================
-- 方法 4: 递归 CTE（SQL Server 2005+）
-- ============================================================
WITH split_cte AS (
    SELECT id, name,
           LEFT(tags, CHARINDEX(',', tags + ',') - 1) AS tag,
           STUFF(tags, 1, CHARINDEX(',', tags + ','), '') AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           LEFT(remaining, CHARINDEX(',', remaining + ',') - 1),
           STUFF(remaining, 1, CHARINDEX(',', remaining + ','), ''),
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
