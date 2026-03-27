-- KingbaseES: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/
--   [2] KingbaseES Documentation - SQL Reference
--       https://help.kingbase.com.cn/v8/

-- ============================================================
-- PIVOT: CASE WHEN + GROUP BY（兼容 PostgreSQL）
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- FILTER 子句
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- Oracle 兼容模式: PIVOT / UNPIVOT
-- ============================================================
-- KingbaseES Oracle 模式支持原生 PIVOT/UNPIVOT
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- ============================================================
-- UNPIVOT: LATERAL + VALUES
-- ============================================================
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES ('Q1', s.Q1), ('Q2', s.Q2), ('Q3', s.Q3), ('Q4', s.Q4)
) AS v(quarter, amount);

-- ============================================================
-- UNPIVOT: UNION ALL
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- 注意事项
-- ============================================================
-- KingbaseES 兼容 PostgreSQL，支持 FILTER / LATERAL
-- Oracle 兼容模式下支持原生 PIVOT/UNPIVOT
-- PostgreSQL 模式下使用 CASE WHEN + GROUP BY
-- 支持 crosstab（需要 tablefunc 扩展）
