-- Amazon Redshift: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Amazon Redshift Documentation
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html

-- ============================================================
-- 准备数据
-- ============================================================

-- CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 生成日期序列
-- ============================================================

-- Redshift 不支持递归 CTE 和 generate_series (FROM 子句)
-- 使用系统表生成序列
WITH date_seq AS (
    SELECT DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY 1) - 1,
           DATE '2024-01-01') AS d
    FROM stl_connection_log LIMIT 10
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_seq ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- ============================================================
-- 2. COALESCE 填零
-- ============================================================

-- SELECT date, COALESCE(amount, 0) AS amount FROM date_series LEFT JOIN daily_sales ...

-- ============================================================
-- 3. 用最近已知值填充
-- ============================================================

-- COUNT 分组法模拟 IGNORE NULLS
-- WITH filled AS (
--     SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp
--     FROM ...
-- )
-- SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) FROM filled;

-- ============================================================
-- 4. 累计和
-- ============================================================

-- SUM(COALESCE(amount, 0)) OVER (ORDER BY date) AS running_total

-- 注意：Amazon Redshift 的日期序列生成方式见上述代码
-- 注意：使用 COALESCE 将缺失值替换为 0
-- 注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
