-- Oracle: PIVOT / UNPIVOT（11g+ 原生支持）
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - PIVOT and UNPIVOT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html#GUID-CFA006CA-6FF1-4972-821E-6996142A51C6
--   [2] Oracle SQL Language Reference - SELECT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [3] Oracle XML DB - PIVOT XML
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- PIVOT: 原生语法（11g+）
-- ============================================================
-- 基本 PIVOT
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- 多聚合函数
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount) AS total,
    COUNT(amount) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);
-- 结果列名: Q1_TOTAL, Q1_CNT, Q2_TOTAL, Q2_CNT, ...

-- 多列 PIVOT
SELECT * FROM (
    SELECT department, job_title, salary
    FROM employees
)
PIVOT (
    AVG(salary)
    FOR job_title IN ('Manager' AS mgr, 'Developer' AS dev, 'Analyst' AS analyst)
);

-- ============================================================
-- PIVOT: CASE WHEN 替代方法（全版本）
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- DECODE 方法（Oracle 专有，更紧凑）
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: 原生语法（11g+）
-- ============================================================
-- 基本 UNPIVOT
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- INCLUDE NULLS（默认排除 NULL 行）
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- 自定义列值
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1 AS 'First Quarter', Q2 AS 'Second Quarter',
                           Q3 AS 'Third Quarter', Q4 AS 'Fourth Quarter')
);

-- 多列 UNPIVOT
SELECT * FROM employee_contacts
UNPIVOT (
    (contact_value, contact_type) FOR contact_kind IN (
        (home_phone, home_type) AS 'Home',
        (work_phone, work_type) AS 'Work'
    )
);

-- ============================================================
-- UNPIVOT: UNION ALL 替代方法（全版本）
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- 动态 PIVOT: PIVOT XML（11g+）
-- ============================================================
-- 使用 XML 类型动态生成列
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT XML (
    SUM(amount)
    FOR quarter IN (SELECT DISTINCT quarter FROM sales)
);
-- 结果以 XML 格式返回，IN 子查询允许动态列

-- ============================================================
-- 动态 PIVOT: 使用 PL/SQL
-- ============================================================
DECLARE
    v_sql    CLOB;
    v_cols   CLOB;
BEGIN
    SELECT LISTAGG('''' || quarter || ''' AS ' || quarter, ', ')
           WITHIN GROUP (ORDER BY quarter)
    INTO v_cols
    FROM (SELECT DISTINCT quarter FROM sales);

    v_sql := 'SELECT * FROM (SELECT product, quarter, amount FROM sales) ' ||
             'PIVOT (SUM(amount) FOR quarter IN (' || v_cols || '))';
    -- EXECUTE IMMEDIATE v_sql;
    DBMS_OUTPUT.PUT_LINE(v_sql);
END;
/

-- ============================================================
-- 注意事项
-- ============================================================
-- PIVOT/UNPIVOT 从 Oracle 11g 开始原生支持
-- PIVOT 子查询中未被 PIVOT 或 FOR 使用的列自动成为 GROUP BY 列
-- PIVOT XML 允许在 IN 子句中使用子查询（动态列）
-- UNPIVOT 默认排除 NULL 值行（使用 INCLUDE NULLS 保留）
-- PIVOT/UNPIVOT 不能与 ORDER BY 一起出现在同一 SELECT 中（需包装子查询）
