-- StarRocks: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] StarRocks Documentation - SELECT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/
--   [2] StarRocks Documentation - Aggregate Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/aggregate-functions/

-- ============================================================
-- 注意：StarRocks 没有原生 PIVOT / UNPIVOT 语法
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
-- UNPIVOT: CROSS JOIN + 子查询
-- ============================================================
SELECT
    s.product,
    q.quarter,
    CASE q.quarter
        WHEN 'Q1' THEN s.Q1
        WHEN 'Q2' THEN s.Q2
        WHEN 'Q3' THEN s.Q3
        WHEN 'Q4' THEN s.Q4
    END AS amount
FROM quarterly_sales s
CROSS JOIN (
    SELECT 'Q1' AS quarter UNION ALL
    SELECT 'Q2' UNION ALL
    SELECT 'Q3' UNION ALL
    SELECT 'Q4'
) q;

-- ============================================================
-- 注意事项
-- ============================================================
-- StarRocks 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 和 IF() 是标准方法
-- MPP 架构下聚合性能优异
-- 向量化执行引擎使 CASE WHEN 高效
-- 动态 PIVOT 需在客户端构建 SQL
