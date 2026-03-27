-- SAP HANA: PIVOT / UNPIVOT
--
-- 参考资料:
--   [1] SAP HANA SQL Reference - MAP Function
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQL Reference - SELECT
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20fcf24075191014a89e9dc7b8408b26.html

-- ============================================================
-- 注意：SAP HANA 没有原生 PIVOT / UNPIVOT 语法
-- 使用 CASE WHEN + GROUP BY 实现 PIVOT
-- 使用 UNION ALL 实现 UNPIVOT
-- SAP HANA 的 MAP 函数可简化条件表达式
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

-- MAP 函数（SAP HANA 特有，类似 DECODE）
SELECT
    product,
    SUM(MAP(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(MAP(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(MAP(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(MAP(quarter, 'Q4', amount, 0)) AS Q4
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
-- 动态 PIVOT（使用 SQLScript 存储过程）
-- ============================================================
CREATE PROCEDURE dynamic_pivot()
LANGUAGE SQLSCRIPT AS
BEGIN
    DECLARE sql_str NCLOB;
    DECLARE col_list NCLOB;

    SELECT STRING_AGG(
        'SUM(CASE WHEN quarter = ''' || quarter || ''' THEN amount ELSE 0 END) AS "' || quarter || '"',
        ', '
    ) INTO col_list
    FROM (SELECT DISTINCT quarter FROM sales ORDER BY quarter);

    sql_str := 'SELECT product, ' || col_list || ' FROM sales GROUP BY product';
    EXEC sql_str;
END;

-- ============================================================
-- 注意事项
-- ============================================================
-- SAP HANA 没有原生 PIVOT/UNPIVOT 语法
-- MAP 函数是 CASE WHEN 的简洁替代
-- 动态 PIVOT 需要 SQLScript 存储过程
-- SAP HANA 的列存储特性使聚合查询性能优异
-- LOB 类型列不能直接用于 GROUP BY
