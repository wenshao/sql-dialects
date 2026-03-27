-- Amazon Redshift: PIVOT / UNPIVOT（原生支持）
--
-- 参考资料:
--   [1] Amazon Redshift Documentation - PIVOT
--       https://docs.aws.amazon.com/redshift/latest/dg/r_FROM_clause-pivot-unpivot.html
--   [2] Amazon Redshift Documentation - UNPIVOT
--       https://docs.aws.amazon.com/redshift/latest/dg/r_FROM_clause-pivot-unpivot.html

-- ============================================================
-- PIVOT: 原生语法
-- ============================================================
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

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
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- INCLUDE NULLS
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- ============================================================
-- UNPIVOT: UNION ALL 替代方法
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
-- Redshift 原生支持 PIVOT 和 UNPIVOT
-- PIVOT 只支持单个聚合函数
-- UNPIVOT 默认排除 NULL 行
-- 大表上的 PIVOT/UNPIVOT 受分布键和排序键影响
-- SUPER 类型列不能用于 PIVOT/UNPIVOT
