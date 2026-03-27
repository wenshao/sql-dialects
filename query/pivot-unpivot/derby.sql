-- Apache Derby: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Apache Derby Reference Manual - SELECT
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj41360.html
--   [2] Apache Derby Reference Manual - CASE Expression
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj31783.html

-- ============================================================
-- 注意：Derby 没有原生 PIVOT / UNPIVOT 语法
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

-- COUNT + CASE
SELECT
    department,
    COUNT(CASE WHEN status = 'active' THEN 1 END) AS active_count,
    COUNT(CASE WHEN status = 'inactive' THEN 1 END) AS inactive_count
FROM employees
GROUP BY department;

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
-- UNPIVOT: VALUES + CROSS JOIN
-- ============================================================
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
CROSS JOIN (VALUES 'Q1', 'Q2', 'Q3', 'Q4') AS q(quarter);

-- ============================================================
-- 注意事项
-- ============================================================
-- Derby 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 是唯一的 PIVOT 方法
-- UNION ALL 和 VALUES + CROSS JOIN 可实现 UNPIVOT
-- 动态 PIVOT 需要在应用层（Java）构建 SQL
-- Derby 的类型系统较严格，CASE 表达式中类型需要一致
