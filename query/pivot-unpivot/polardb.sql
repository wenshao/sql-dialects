-- PolarDB: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] PolarDB Documentation
--       https://www.alibabacloud.com/help/en/polardb/
--   [2] PolarDB for PostgreSQL Documentation
--       https://www.alibabacloud.com/help/en/polardb/polardb-for-postgresql/

-- ============================================================
-- PolarDB for PostgreSQL: CASE WHEN + GROUP BY / FILTER / crosstab
-- ============================================================

-- CASE WHEN + GROUP BY
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

-- crosstab（需要 tablefunc 扩展，PolarDB for PostgreSQL）
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales GROUP BY product, quarter ORDER BY product, quarter',
    'SELECT DISTINCT quarter FROM sales ORDER BY quarter'
) AS ct(product text, Q1 numeric, Q2 numeric, Q3 numeric, Q4 numeric);

-- ============================================================
-- PolarDB for MySQL: IF / CASE WHEN
-- ============================================================
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: LATERAL + VALUES（PolarDB for PostgreSQL）
-- ============================================================
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES ('Q1', s.Q1), ('Q2', s.Q2), ('Q3', s.Q3), ('Q4', s.Q4)
) AS v(quarter, amount);

-- ============================================================
-- UNPIVOT: UNION ALL（通用）
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
-- PolarDB for PostgreSQL 支持 crosstab / FILTER / LATERAL
-- PolarDB for MySQL 使用 IF / CASE WHEN
-- 分布式模式下 PIVOT 可能需要全局聚合
-- 建议在分布键上 GROUP BY 以减少数据移动
