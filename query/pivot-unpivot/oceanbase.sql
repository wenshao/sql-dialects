-- OceanBase: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] OceanBase Documentation
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Documentation - SELECT
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- Oracle 模式: 原生 PIVOT / UNPIVOT（4.0+）
-- ============================================================

-- PIVOT（Oracle 模式）
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- UNPIVOT（Oracle 模式）
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- UNPIVOT INCLUDE NULLS（Oracle 模式）
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- ============================================================
-- MySQL 模式: CASE WHEN + GROUP BY
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- IF 函数（MySQL 模式）
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: UNION ALL（两种模式通用）
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
-- OceanBase Oracle 模式支持原生 PIVOT/UNPIVOT
-- OceanBase MySQL 模式需要 CASE WHEN + GROUP BY
-- 两种模式下 UNION ALL UNPIVOT 方法通用
-- 分布式架构下 PIVOT 聚合可能触发数据重分布
