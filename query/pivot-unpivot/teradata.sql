-- Teradata: PIVOT / UNPIVOT（16.20+ 原生支持）
--
-- 参考资料:
--   [1] Teradata SQL Reference - PIVOT / UNPIVOT
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language/July-2021
--   [2] Teradata Documentation - SELECT
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language/July-2021/SELECT-Statement

-- ============================================================
-- PIVOT: 原生语法（16.20+）
-- ============================================================
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
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
-- UNPIVOT: 原生语法（16.20+）
-- ============================================================
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
) AS unpvt;

-- INCLUDE NULLS
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
) AS unpvt;

-- ============================================================
-- UNPIVOT: UNION ALL 替代方法（全版本）
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- 动态 PIVOT（使用宏）
-- ============================================================
-- Teradata 可通过 REPLACE MACRO 实现
-- 也可使用 BTEQ 脚本动态生成 SQL

-- ============================================================
-- 注意事项
-- ============================================================
-- PIVOT/UNPIVOT 从 16.20 版本开始原生支持
-- 之前版本使用 CASE WHEN + GROUP BY
-- UNPIVOT 默认排除 NULL 行
-- Teradata 的 PIVOT 性能受 AMP 分布影响
