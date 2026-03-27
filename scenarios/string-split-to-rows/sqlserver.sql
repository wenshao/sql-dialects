-- SQL Server: 字符串拆分为行（String Split to Rows）
--
-- 参考资料:
--   [1] SQL Server - STRING_SPLIT
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/string-split-transact-sql

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(100), tags NVARCHAR(500)
);
INSERT INTO tags_csv VALUES
    (N'Alice', N'python,java,sql'),
    (N'Bob',   N'go,rust'),
    (N'Carol', N'sql,python,javascript,typescript');

-- ============================================================
-- 1. STRING_SPLIT（推荐, 2016+）
-- ============================================================
SELECT t.id, t.name, s.value AS tag
FROM tags_csv t CROSS APPLY STRING_SPLIT(t.tags, ',') s;

-- 2022+: 带序号（enable_ordinal = 1）
SELECT t.id, t.name, s.value AS tag, s.ordinal
FROM tags_csv t CROSS APPLY STRING_SPLIT(t.tags, ',', 1) s
ORDER BY t.id, s.ordinal;

-- 设计分析（对引擎开发者）:
--   STRING_SPLIT 是表值函数——通过 CROSS APPLY 使用。
--   2016 初始版本的致命缺陷: 不保证返回顺序！
--   'a,b,c' 可能返回 b,a,c 的顺序。2022 通过 ordinal 参数修复。
--
-- 横向对比:
--   PostgreSQL: string_to_array('a,b,c', ',') → unnest()
--               或 regexp_split_to_table('a,b,c', ',')
--   MySQL:      无内置函数（需要递归 CTE 或 JSON_TABLE）
--   Oracle:     REGEXP_SUBSTR + CONNECT BY（复杂且低效）

-- ============================================================
-- 2. OPENJSON 方法（2016+, 保留顺序）
-- ============================================================
SELECT t.id, t.name, j.value AS tag, j.[key] AS pos
FROM tags_csv t
CROSS APPLY OPENJSON('["' + REPLACE(t.tags, ',', '","') + '"]') j;

-- 技巧: 将 'a,b,c' 转为 '["a","b","c"]'，然后用 OPENJSON 展开 JSON 数组
-- key 是数组索引（保证顺序），这是 2016 版本中唯一保证顺序的方法

-- ============================================================
-- 3. XML 方法（2005+, 最早的可用方案）
-- ============================================================
SELECT t.id, t.name,
       x.node.value('.', 'NVARCHAR(100)') AS tag
FROM tags_csv t
CROSS APPLY (
    SELECT CAST('<x>' + REPLACE(t.tags, ',', '</x><x>') + '</x>' AS XML)
) AS parsed(xml_data)
CROSS APPLY parsed.xml_data.nodes('/x') AS x(node);

-- 注意: 如果数据包含 XML 特殊字符（< > &），此方法会失败

-- ============================================================
-- 4. 递归 CTE 方法（2005+, 保留顺序）
-- ============================================================
;WITH split_cte AS (
    SELECT id, name,
           LEFT(tags, CHARINDEX(',', tags + ',') - 1) AS tag,
           STUFF(tags, 1, CHARINDEX(',', tags + ','), '') AS remaining,
           1 AS pos
    FROM tags_csv
    UNION ALL
    SELECT id, name,
           LEFT(remaining, CHARINDEX(',', remaining + ',') - 1),
           STUFF(remaining, 1, CHARINDEX(',', remaining + ','), ''),
           pos + 1
    FROM split_cte WHERE remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;

-- 设计分析:
--   四种方法的优劣:
--   STRING_SPLIT:  最快，但 2016 版不保证顺序，只支持单字符分隔符
--   OPENJSON:      保证顺序，需要 JSON 转换（额外开销）
--   XML:           2005+ 可用，但 XML 特殊字符问题
--   递归 CTE:      最通用，但递归开销大，大数据集慢
--
-- 对引擎开发者的启示:
--   字符串拆分为行是一个高频需求——几乎每个数据库都需要。
--   PostgreSQL 的 unnest(string_to_array()) 是最优雅的方案（函数组合）。
--   SQL Server 的 STRING_SPLIT 作为表值函数通过 CROSS APPLY 使用，
--   这要求引擎支持"一行输入 → 多行输出"的函数语义。
