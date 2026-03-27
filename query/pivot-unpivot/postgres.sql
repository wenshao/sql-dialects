-- PostgreSQL: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] PostgreSQL Documentation - tablefunc (crosstab)
--       https://www.postgresql.org/docs/current/tablefunc.html
--   [2] PostgreSQL Documentation - Aggregate Functions
--       https://www.postgresql.org/docs/current/functions-aggregate.html
--   [3] PostgreSQL Documentation - FILTER Clause
--       https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES

-- ============================================================
-- PIVOT: CASE WHEN + GROUP BY 方法
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS "Q1",
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS "Q2",
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS "Q3",
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS "Q4"
FROM sales
GROUP BY product;

-- ============================================================
-- PIVOT: FILTER 子句（9.4+，更简洁）
-- ============================================================
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS "Q1",
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS "Q2",
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS "Q3",
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS "Q4"
FROM sales
GROUP BY product;

-- COUNT + FILTER
SELECT
    department,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count,
    COUNT(*) FILTER (WHERE status = 'inactive') AS inactive_count
FROM employees
GROUP BY department;

-- ============================================================
-- PIVOT: crosstab 函数（需要 tablefunc 扩展）
-- ============================================================
-- 安装扩展
CREATE EXTENSION IF NOT EXISTS tablefunc;

-- 基本 crosstab
SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales
     GROUP BY product, quarter
     ORDER BY product, quarter'
) AS ct(product text, "Q1" numeric, "Q2" numeric, "Q3" numeric, "Q4" numeric);

-- 两参数 crosstab（处理缺失值更可靠）
SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales
     GROUP BY product, quarter
     ORDER BY product, quarter',
    'SELECT DISTINCT quarter FROM sales ORDER BY quarter'
) AS ct(product text, "Q1" numeric, "Q2" numeric, "Q3" numeric, "Q4" numeric);

-- ============================================================
-- UNPIVOT: UNION ALL 方法
-- ============================================================
SELECT product, 'Q1' AS quarter, "Q1" AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, "Q2" AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, "Q3" AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, "Q4" AS amount FROM quarterly_sales
ORDER BY product, quarter;

-- ============================================================
-- UNPIVOT: VALUES + LATERAL（更优雅，9.3+）
-- ============================================================
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES
        ('Q1', s."Q1"),
        ('Q2', s."Q2"),
        ('Q3', s."Q3"),
        ('Q4', s."Q4")
) AS v(quarter, amount);

-- 过滤 NULL 值
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES
        ('Q1', s."Q1"),
        ('Q2', s."Q2"),
        ('Q3', s."Q3"),
        ('Q4', s."Q4")
) AS v(quarter, amount)
WHERE v.amount IS NOT NULL;

-- ============================================================
-- UNPIVOT: unnest + array（PostgreSQL 特有）
-- ============================================================
SELECT
    product,
    unnest(ARRAY['Q1', 'Q2', 'Q3', 'Q4']) AS quarter,
    unnest(ARRAY["Q1", "Q2", "Q3", "Q4"]) AS amount
FROM quarterly_sales;

-- ============================================================
-- 动态 PIVOT（使用动态 SQL）
-- ============================================================
-- PostgreSQL 无原生动态 PIVOT，需要 PL/pgSQL
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
    -- EXECUTE sql_text;  -- 在函数中使用
END $$;

-- ============================================================
-- 注意事项
-- ============================================================
-- PostgreSQL 没有原生 PIVOT/UNPIVOT 语法
-- crosstab 需要 tablefunc 扩展
-- FILTER 子句比 CASE WHEN 更简洁高效（9.4+）
-- LATERAL + VALUES 是 UNPIVOT 的最佳方式
-- 动态 PIVOT 需要 PL/pgSQL 动态 SQL
