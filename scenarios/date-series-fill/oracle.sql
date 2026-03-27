-- Oracle: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Oracle Documentation - CONNECT BY
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Hierarchical-Queries.html
--   [2] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    NUMBER(10,2)
);
INSERT ALL
    INTO daily_sales VALUES (DATE '2024-01-01', 100)
    INTO daily_sales VALUES (DATE '2024-01-02', 150)
    INTO daily_sales VALUES (DATE '2024-01-04', 200)
    INTO daily_sales VALUES (DATE '2024-01-05', 120)
    INTO daily_sales VALUES (DATE '2024-01-08', 300)
    INTO daily_sales VALUES (DATE '2024-01-09', 250)
    INTO daily_sales VALUES (DATE '2024-01-10', 180)
SELECT 1 FROM DUAL;

-- ============================================================
-- 1. 使用 CONNECT BY LEVEL 生成日期序列
-- ============================================================

SELECT DATE '2024-01-01' + LEVEL - 1 AS d
FROM DUAL
CONNECT BY LEVEL <= DATE '2024-01-10' - DATE '2024-01-01' + 1;

-- 按月生成
SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS month_start
FROM DUAL
CONNECT BY LEVEL <= 12;

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

SELECT
    seq.d                      AS date_val,
    COALESCE(ds.amount, 0)     AS amount
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL
    CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;

-- ============================================================
-- 3. COALESCE 填零 + 累计和
-- ============================================================

SELECT
    seq.d                      AS date_val,
    COALESCE(ds.amount, 0)     AS amount,
    SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY seq.d) AS running_total
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;

-- ============================================================
-- 4. 用最近已知值填充（Oracle 支持 IGNORE NULLS）
-- ============================================================

-- Oracle 原生支持 LAST_VALUE ... IGNORE NULLS
SELECT
    seq.d AS date_val,
    LAST_VALUE(ds.amount IGNORE NULLS)
        OVER (ORDER BY seq.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
        AS filled_amount
FROM (
    SELECT DATE '2024-01-01' + LEVEL - 1 AS d
    FROM DUAL CONNECT BY LEVEL <= 10
) seq
LEFT JOIN daily_sales ds ON ds.sale_date = seq.d
ORDER BY seq.d;

-- 也可以使用 LAG IGNORE NULLS
-- LAG(amount IGNORE NULLS) OVER (ORDER BY d)

-- ============================================================
-- 5. 递归 CTE 方法（Oracle 11gR2+）
-- ============================================================

WITH date_series(d) AS (
    SELECT DATE '2024-01-01' FROM DUAL
    UNION ALL
    SELECT d + 1 FROM date_series WHERE d < DATE '2024-01-10'
)
SELECT ds2.d AS date_val, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 6. MODEL 子句（Oracle 特有的高级间隙填充）
-- ============================================================

SELECT date_val, amount FROM daily_sales
MODEL
    DIMENSION BY (sale_date AS date_val)
    MEASURES (amount)
    RULES (
        amount[FOR date_val FROM DATE '2024-01-01' TO DATE '2024-01-10'
               INCREMENT INTERVAL '1' DAY] =
            COALESCE(amount[CV(date_val)], 0)
    )
ORDER BY date_val;

-- 注意：CONNECT BY LEVEL 是 Oracle 特有的序列生成方法
-- 注意：Oracle 原生支持 IGNORE NULLS（LAST_VALUE、LAG、LEAD 等）
-- 注意：MODEL 子句是 Oracle 独特的多维数据处理功能
-- 注意：日期相减在 Oracle 中直接返回天数
