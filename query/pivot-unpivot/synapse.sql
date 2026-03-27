-- Azure Synapse Analytics: PIVOT / UNPIVOT（原生支持）
--
-- 参考资料:
--   [1] Microsoft Docs - FROM clause plus PIVOT and UNPIVOT
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql
--   [2] Microsoft Docs - Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- ============================================================
-- PIVOT: 原生语法（兼容 SQL Server）
-- ============================================================
SELECT product, [Q1], [Q2], [Q3], [Q4]
FROM (
    SELECT product, quarter, amount
    FROM sales
) AS src
PIVOT (
    SUM(amount)
    FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- ============================================================
-- PIVOT: CASE WHEN 替代方法
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
-- UNPIVOT: 原生语法
-- ============================================================
SELECT product, quarter, amount
FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS unpvt;

-- ============================================================
-- UNPIVOT: CROSS APPLY + VALUES
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

-- ============================================================
-- 动态 PIVOT
-- ============================================================
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

SELECT @cols = STRING_AGG(QUOTENAME(quarter), ', ')
FROM (SELECT DISTINCT quarter FROM sales) AS q;

SET @sql = N'
SELECT product, ' + @cols + N'
FROM (SELECT product, quarter, amount FROM sales) AS src
PIVOT (SUM(amount) FOR quarter IN (' + @cols + N')) AS pvt';

EXEC sp_executesql @sql;

-- ============================================================
-- 注意事项
-- ============================================================
-- 兼容 SQL Server T-SQL 的 PIVOT/UNPIVOT 语法
-- 专用 SQL 池和无服务器 SQL 池都支持
-- PIVOT 只支持单个聚合函数
-- CROSS APPLY + VALUES 是灵活的 UNPIVOT 替代方案
-- 分布式架构下 PIVOT 聚合受分布键影响
