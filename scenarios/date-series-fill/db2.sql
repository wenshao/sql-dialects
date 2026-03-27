-- IBM DB2: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] IBM DB2 Documentation
--       https://www.ibm.com/docs/en/db2/11.5?topic=queries-recursive-common-table-expressions
--   [2] IBM DB2 Documentation
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-scalar

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));

-- ============================================================
-- DB2 日期序列：使用递归 CTE
-- ============================================================

WITH date_series(d) AS (
    SELECT DATE '2024-01-01' FROM SYSIBM.SYSDUMMY1
    UNION ALL
    SELECT d + 1 DAY FROM date_series WHERE d < DATE '2024-01-10'
)
SELECT ds2.d, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- LEFT JOIN 填充间隙 + COALESCE 填零
-- ============================================================

-- 使用上述日期序列 LEFT JOIN 原始数据
-- COALESCE(amount, 0) 将 NULL 替换为 0

-- ============================================================
-- 用最近已知值填充
-- ============================================================

-- COUNT 分组法模拟 IGNORE NULLS
-- WITH filled AS (
--     SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
--     FROM date_series LEFT JOIN daily_sales ...
-- )
-- SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled
-- FROM filled;

-- 注意：IBM DB2 的日期序列生成方式见上述特有语法
-- 注意：使用 COALESCE 进行空值替换
-- 注意：COUNT 分组法是模拟 IGNORE NULLS 的通用方案
