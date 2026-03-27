-- Hive: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Select
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
--   [2] Apache Hive Language Manual - Lateral View
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView

-- ============================================================
-- 注意：Hive 没有原生 PIVOT / UNPIVOT 语法
-- 使用 CASE WHEN + GROUP BY 实现 PIVOT
-- 使用 LATERAL VIEW + stack / UNION ALL 实现 UNPIVOT
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

-- collect_list + CASE（生成数组）
SELECT
    product,
    collect_list(CASE WHEN quarter = 'Q1' THEN amount END) AS Q1_values
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: LATERAL VIEW + stack（推荐）
-- ============================================================
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) t AS quarter, amount;

-- 过滤 NULL
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) t AS quarter, amount
WHERE amount IS NOT NULL;

-- ============================================================
-- UNPIVOT: LATERAL VIEW + explode（数组场景）
-- ============================================================
-- 使用 map 和 explode
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW explode(
    map('Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
) t AS quarter, amount;

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
-- Hive 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 是标准行转列方法
-- LATERAL VIEW + stack() 是最佳的列转行方法
-- LATERAL VIEW + explode(map()) 也可以实现 UNPIVOT
-- 动态 PIVOT 需要在客户端构建 SQL
-- 大数据量下 UNION ALL 比 stack() 效率低（多次扫描）
