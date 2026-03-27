-- MariaDB: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] MariaDB Documentation - GROUP BY
--       https://mariadb.com/kb/en/group-by/
--   [2] MariaDB Documentation - CASE
--       https://mariadb.com/kb/en/case-operator/
--   [3] MariaDB Documentation - Prepared Statements
--       https://mariadb.com/kb/en/prepare-statement/

-- ============================================================
-- 注意：MariaDB 没有原生 PIVOT / UNPIVOT 语法
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

-- GROUP_CONCAT 转列
SELECT
    product,
    GROUP_CONCAT(CASE WHEN quarter = 'Q1' THEN amount END) AS Q1
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
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales
ORDER BY product, quarter;

-- ============================================================
-- UNPIVOT: CTE + CROSS JOIN（10.2+）
-- ============================================================
WITH quarters AS (
    SELECT 'Q1' AS quarter UNION ALL
    SELECT 'Q2' UNION ALL
    SELECT 'Q3' UNION ALL
    SELECT 'Q4'
)
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
CROSS JOIN quarters q;

-- ============================================================
-- 动态 PIVOT（Prepared Statement）
-- ============================================================
SET @sql = NULL;
SELECT GROUP_CONCAT(DISTINCT
    CONCAT('SUM(IF(quarter = ''', quarter, ''', amount, 0)) AS `', quarter, '`')
) INTO @sql
FROM sales;

SET @sql = CONCAT('SELECT product, ', @sql, ' FROM sales GROUP BY product');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================================
-- 注意事项
-- ============================================================
-- MariaDB 没有原生 PIVOT/UNPIVOT 语法
-- CASE WHEN + GROUP BY 和 IF() 是行转列的标准方法
-- 动态 PIVOT 需要 Prepared Statement
-- GROUP_CONCAT 默认最大长度 1024，可调整 group_concat_max_len
-- 10.2+ 支持 CTE，可更优雅地实现 UNPIVOT
