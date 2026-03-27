-- SQL Server: PIVOT / UNPIVOT（2005+ 原生支持）
--
-- 参考资料:
--   [1] Microsoft Docs - FROM clause plus PIVOT and UNPIVOT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql?view=sql-server-ver16#pivot-and-unpivot
--   [2] Microsoft Docs - Using PIVOT and UNPIVOT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot
--   [3] Microsoft Docs - Dynamic PIVOT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql

-- ============================================================
-- PIVOT: 原生语法（2005+）
-- ============================================================
-- 基本 PIVOT
SELECT product, [Q1], [Q2], [Q3], [Q4]
FROM (
    SELECT product, quarter, amount
    FROM sales
) AS src
PIVOT (
    SUM(amount)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- 多分组列（非 PIVOT 列自动成为分组列）
SELECT department, product, [Q1], [Q2], [Q3], [Q4]
FROM (
    SELECT department, product, quarter, amount
    FROM sales
) AS src
PIVOT (
    SUM(amount)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- 使用不同聚合函数
SELECT product, [Q1], [Q2], [Q3], [Q4]
FROM (
    SELECT product, quarter, amount
    FROM sales
) AS src
PIVOT (
    AVG(amount)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- ============================================================
-- PIVOT: CASE WHEN 替代方法（全版本）
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: 原生语法（2005+）
-- ============================================================
-- 基本 UNPIVOT
SELECT product, quarter, amount
FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS unpvt;

-- UNPIVOT 不会保留 NULL 值的行
-- 如需保留 NULL，先替换为默认值
SELECT product, quarter, amount
FROM (
    SELECT product,
        ISNULL(Q1, 0) AS Q1,
        ISNULL(Q2, 0) AS Q2,
        ISNULL(Q3, 0) AS Q3,
        ISNULL(Q4, 0) AS Q4
    FROM quarterly_sales
) AS src
UNPIVOT (
    amount FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS unpvt;

-- ============================================================
-- UNPIVOT: CROSS APPLY + VALUES 替代方法（2008+）
-- ============================================================
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS APPLY (
    VALUES
        ('Q1', s.Q1),
        ('Q2', s.Q2),
        ('Q3', s.Q3),
        ('Q4', s.Q4)
) AS v(quarter, amount);

-- 过滤 NULL
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS APPLY (
    VALUES
        ('Q1', s.Q1),
        ('Q2', s.Q2),
        ('Q3', s.Q3),
        ('Q4', s.Q4)
) AS v(quarter, amount)
WHERE v.amount IS NOT NULL;

-- ============================================================
-- 动态 PIVOT
-- ============================================================
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

-- 动态获取列名
SELECT @cols = STRING_AGG(QUOTENAME(quarter), ', ')
FROM (SELECT DISTINCT quarter FROM sales) AS q;

-- 构建动态 SQL
SET @sql = N'
SELECT product, ' + @cols + N'
FROM (SELECT product, quarter, amount FROM sales) AS src
PIVOT (SUM(amount) FOR quarter IN (' + @cols + N')) AS pvt';

EXEC sp_executesql @sql;

-- 2016 之前版本（使用 FOR XML PATH 替代 STRING_AGG）
SELECT @cols = STUFF((
    SELECT DISTINCT ', ' + QUOTENAME(quarter)
    FROM sales
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '');

-- ============================================================
-- 动态 UNPIVOT
-- ============================================================
DECLARE @unpivot_cols NVARCHAR(MAX), @unpivot_sql NVARCHAR(MAX);

SELECT @unpivot_cols = STRING_AGG(QUOTENAME(COLUMN_NAME), ', ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'quarterly_sales'
  AND COLUMN_NAME LIKE 'Q%';

SET @unpivot_sql = N'
SELECT product, quarter, amount
FROM quarterly_sales
UNPIVOT (amount FOR quarter IN (' + @unpivot_cols + N')) AS unpvt';

EXEC sp_executesql @unpivot_sql;

-- ============================================================
-- 注意事项
-- ============================================================
-- PIVOT/UNPIVOT 从 SQL Server 2005 开始原生支持
-- PIVOT 中只能使用一个聚合函数（不像 Oracle 支持多个）
-- UNPIVOT 默认不保留 NULL 值的行
-- CROSS APPLY + VALUES 是 UNPIVOT 的灵活替代方案
-- 动态 PIVOT 需要 sp_executesql 或 EXEC
-- 注意 SQL 注入风险：使用 QUOTENAME 保护列名
