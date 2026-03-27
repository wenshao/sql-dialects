-- H2: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] H2 Database Documentation - SELECT
--       https://h2database.com/html/commands.html#select
--   [2] H2 Database Documentation - CASE
--       https://h2database.com/html/functions-aggregate.html

-- ============================================================
-- 注意：H2 没有原生 PIVOT / UNPIVOT 语法
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

-- DECODE 函数（H2 支持）
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- FILTER 子句（2.0+）
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS Q4
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
-- UNPIVOT: VALUES + CROSS JOIN（2.0+）
-- ============================================================
SELECT
    s.product,
    v.quarter,
    CASE v.quarter
        WHEN 'Q1' THEN s.Q1
        WHEN 'Q2' THEN s.Q2
        WHEN 'Q3' THEN s.Q3
        WHEN 'Q4' THEN s.Q4
    END AS amount
FROM quarterly_sales s
CROSS JOIN (VALUES ('Q1'), ('Q2'), ('Q3'), ('Q4')) AS v(quarter);

-- ============================================================
-- 注意事项
-- ============================================================
-- H2 没有原生 PIVOT/UNPIVOT 语法
-- 支持 DECODE 函数和 FILTER 子句
-- FILTER 子句从 2.0 版本开始支持
-- H2 的兼容模式（MySQL/PostgreSQL/Oracle）不影响 PIVOT 能力
-- 动态 PIVOT 需要在应用层构建 SQL
