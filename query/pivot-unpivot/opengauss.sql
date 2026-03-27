-- openGauss: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] openGauss Documentation - SELECT
--       https://docs.opengauss.org/en/docs/latest/docs/SQLReference/SELECT.html
--   [2] openGauss Documentation - tablefunc
--       https://docs.opengauss.org/en/docs/latest/docs/SQLReference/

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
-- PIVOT: crosstab（需要 tablefunc 扩展）
-- ============================================================
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales GROUP BY product, quarter ORDER BY product, quarter',
    'SELECT DISTINCT quarter FROM sales ORDER BY quarter'
) AS ct(product text, Q1 numeric, Q2 numeric, Q3 numeric, Q4 numeric);

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
-- 动态 PIVOT（PL/pgSQL）
-- ============================================================
DO $$
DECLARE
    sql_text text;
    col_list text;
BEGIN
    SELECT string_agg(
        format('SUM(CASE WHEN quarter = %L THEN amount ELSE 0 END) AS %I', quarter, quarter),
        ', '
    ) INTO col_list
    FROM (SELECT DISTINCT quarter FROM sales ORDER BY quarter) q;

    sql_text := format('SELECT product, %s FROM sales GROUP BY product', col_list);
    RAISE NOTICE '%', sql_text;
END $$;

-- ============================================================
-- 注意事项
-- ============================================================
-- openGauss 兼容 PostgreSQL，支持 FILTER / crosstab / LATERAL
-- tablefunc 扩展需要单独安装
-- 动态 PIVOT 通过 PL/pgSQL 实现
-- 分布式部署下 PIVOT 可能需要数据重分布
