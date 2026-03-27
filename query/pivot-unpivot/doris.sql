-- Apache Doris: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Apache Doris Documentation - SELECT
--       https://doris.apache.org/docs/sql-manual/sql-statements/query/SELECT/
--   [2] Apache Doris Documentation - Aggregate Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/aggregate-functions/

-- ============================================================
-- 注意：Doris 没有原生 PIVOT / UNPIVOT 语法
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

-- IF 函数
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
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
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- UNPIVOT: LATERAL VIEW + explode_split（Doris 2.0+）
-- ============================================================
-- 使用 LATERAL VIEW 和数组函数
SELECT product, quarter, amount
FROM quarterly_sales
CROSS JOIN LATERAL (
    SELECT 'Q1' AS quarter, Q1 AS amount UNION ALL
    SELECT 'Q2', Q2 UNION ALL
    SELECT 'Q3', Q3 UNION ALL
    SELECT 'Q4', Q4
) t;

-- ============================================================
-- 注意事项
-- ============================================================
-- Doris 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 和 IF() 是行转列的标准方法
-- MPP 架构下聚合操作性能优异
-- BITMAP 和 HLL 列不能直接用于 CASE WHEN
-- 动态 PIVOT 需要在客户端构建 SQL
