-- DB2: PIVOT / UNPIVOT（11.1+ 原生支持）
--
-- 参考资料:
--   [1] IBM DB2 Documentation - PIVOT clause
--       https://www.ibm.com/docs/en/db2/11.5?topic=queries-pivot-clause
--   [2] IBM DB2 Documentation - UNPIVOT clause
--       https://www.ibm.com/docs/en/db2/11.5?topic=queries-unpivot-clause
--   [3] IBM DB2 Documentation - SELECT
--       https://www.ibm.com/docs/en/db2/11.5?topic=statements-select

-- ============================================================
-- PIVOT: 原生语法（11.1+）
-- ============================================================
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
) AS pvt;

-- 多聚合
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount) AS total,
    AVG(amount) AS average
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
-- UNPIVOT: 原生语法（11.1+）
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

-- LATERAL + VALUES 方法
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s,
    LATERAL (VALUES
        ('Q1', s.Q1),
        ('Q2', s.Q2),
        ('Q3', s.Q3),
        ('Q4', s.Q4)
    ) AS v(quarter, amount);

-- ============================================================
-- 动态 PIVOT
-- ============================================================
-- 使用 DB2 动态 SQL
-- EXECUTE IMMEDIATE 或 PREPARE/EXECUTE 语句

-- ============================================================
-- 注意事项
-- ============================================================
-- PIVOT/UNPIVOT 从 DB2 11.1 开始原生支持
-- 支持多聚合函数
-- UNPIVOT 默认排除 NULL 行
-- LATERAL + VALUES 是灵活的 UNPIVOT 替代方案
-- 旧版本可用 CASE WHEN + GROUP BY
