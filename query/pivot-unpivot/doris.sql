-- Apache Doris: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Doris Documentation - SELECT
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- Doris 没有原生 PIVOT / UNPIVOT 语法
-- ============================================================

-- PIVOT: CASE WHEN + GROUP BY
SELECT product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales GROUP BY product;

-- IF 函数简写
SELECT product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2
FROM sales GROUP BY product;

-- UNPIVOT: UNION ALL
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2', Q2 FROM quarterly_sales
UNION ALL
SELECT product, 'Q3', Q3 FROM quarterly_sales
UNION ALL
SELECT product, 'Q4', Q4 FROM quarterly_sales;

-- LATERAL VIEW (2.0+)
SELECT product, quarter, amount FROM quarterly_sales
CROSS JOIN LATERAL (
    SELECT 'Q1' AS quarter, Q1 AS amount UNION ALL SELECT 'Q2', Q2
    UNION ALL SELECT 'Q3', Q3 UNION ALL SELECT 'Q4', Q4
) t;

-- 对比: BigQuery/SQL Server 有原生 PIVOT/UNPIVOT。
-- Doris/StarRocks/ClickHouse/MySQL 都需要手动实现。
