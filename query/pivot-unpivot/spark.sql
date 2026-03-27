-- Spark SQL: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Spark SQL Documentation - PIVOT
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-pivot.html
--   [2] Spark SQL Documentation - UNPIVOT
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-unpivot.html

-- ============================================================
-- PIVOT: 原生语法（2.4+）
-- ============================================================
-- 基本 PIVOT
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

-- 多聚合
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount) AS total,
    AVG(amount) AS average
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

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
-- UNPIVOT: 原生语法（3.4+）
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
-- UNPIVOT: stack 函数（全版本）
-- ============================================================
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) AS quarter, amount;

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
-- PIVOT 从 Spark 2.4 开始支持
-- UNPIVOT 从 Spark 3.4 开始原生支持
-- 之前版本使用 stack() 函数做 UNPIVOT
-- PIVOT 支持多聚合函数
-- 注意：PIVOT 的 IN 值列表必须是字面量，不能是子查询
-- 动态 PIVOT 需要在应用层构建 SQL
