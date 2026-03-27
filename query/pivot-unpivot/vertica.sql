-- Vertica: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Vertica Documentation - Aggregate Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Aggregate/AggregateFunctions.htm
--   [2] Vertica Documentation - SELECT
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/SELECT/SELECT.htm

-- ============================================================
-- 注意：Vertica 没有原生 PIVOT / UNPIVOT 语法
-- 使用 CASE WHEN + GROUP BY 实现 PIVOT
-- 使用 UNION ALL 实现 UNPIVOT
-- ============================================================

-- ============================================================
-- PIVOT: CASE WHEN + GROUP BY
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- DECODE 函数
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: UNION ALL
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales
ORDER BY product, quarter;

-- ============================================================
-- UNPIVOT: CROSS JOIN + CASE
-- ============================================================
WITH quarters AS (
    SELECT 'Q1' AS quarter UNION ALL SELECT 'Q2' UNION ALL SELECT 'Q3' UNION ALL SELECT 'Q4'
)
SELECT
    s.product,
    q.quarter,
    CASE q.quarter
        WHEN 'Q1' THEN s.Q1
        WHEN 'Q2' THEN s.Q2
        WHEN 'Q3' THEN s.Q3
        WHEN 'Q4' THEN s.Q4
    END AS amount
FROM quarterly_sales s
CROSS JOIN quarters q;

-- ============================================================
-- 注意事项
-- ============================================================
-- Vertica 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 是标准行转列方法
-- 作为列存储数据库，聚合操作性能优异
-- 动态 PIVOT 需要在应用层或存储过程中构建 SQL
