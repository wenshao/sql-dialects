-- MaxCompute（ODPS）: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] MaxCompute Documentation - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select-syntax
--   [2] MaxCompute Documentation - Aggregate Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/aggregate-functions

-- ============================================================
-- 注意：MaxCompute 没有原生 PIVOT / UNPIVOT 语法
-- 使用 CASE WHEN + GROUP BY 实现 PIVOT
-- 使用 UNION ALL / LATERAL VIEW 实现 UNPIVOT
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
-- UNPIVOT: LATERAL VIEW + explode（推荐）
-- ============================================================
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW explode(
    map('Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
) t AS quarter, amount;

-- LATERAL VIEW + posexplode
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW posexplode(
    array(Q1, Q2, Q3, Q4)
) t AS pos, amount
LATERAL VIEW posexplode(
    array('Q1', 'Q2', 'Q3', 'Q4')
) t2 AS pos2, quarter
WHERE t.pos = t2.pos2;

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
-- MaxCompute 没有原生 PIVOT/UNPIVOT 语法
-- LATERAL VIEW + explode(map()) 是最佳 UNPIVOT 方法
-- CASE WHEN + GROUP BY 是标准行转列方法
-- 大数据量下避免使用 UNION ALL 做 UNPIVOT（多次全表扫描）
-- 动态 PIVOT 需在 ODPS 客户端或 DataWorks 中构建 SQL
