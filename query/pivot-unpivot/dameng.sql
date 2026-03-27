-- 达梦（DM）: PIVOT / UNPIVOT（原生支持）
--
-- 参考资料:
--   [1] 达梦数据库 SQL 语言手册 - PIVOT / UNPIVOT
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-query.html
--   [2] 达梦数据库 SQL 语言手册 - SELECT
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/

-- ============================================================
-- PIVOT: 原生语法（兼容 Oracle 11g+）
-- ============================================================
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- 多聚合
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount) AS total,
    COUNT(amount) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

-- ============================================================
-- PIVOT: CASE WHEN 替代方法
-- ============================================================
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

-- DECODE 函数
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

-- ============================================================
-- UNPIVOT: 原生语法
-- ============================================================
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- INCLUDE NULLS
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

-- ============================================================
-- UNPIVOT: UNION ALL 替代方法
-- ============================================================
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

-- ============================================================
-- 动态 PIVOT（PL/SQL）
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
    EXECUTE IMMEDIATE v_sql;
END;

-- ============================================================
-- 注意事项
-- ============================================================
-- 达梦兼容 Oracle，原生支持 PIVOT/UNPIVOT
-- 支持 DECODE 函数
-- UNPIVOT 默认排除 NULL 行
-- 动态 PIVOT 可通过 PL/SQL 实现
-- LOB 列有使用限制
