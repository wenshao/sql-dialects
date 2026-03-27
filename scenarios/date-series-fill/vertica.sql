-- Vertica: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Vertica Documentation
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/TimeSeries/TimeSeriesFunctions.htm
--   [2] Vertica Documentation
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/AnalyticFunctions.htm

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));

-- ============================================================
-- Vertica 特有：TIMESERIES 子句
-- ============================================================

-- TIMESERIES 自动生成时间序列并填充间隙
SELECT ts::DATE AS date, TS_FIRST_VALUE(amount) AS amount
FROM daily_sales
TIMESERIES ts AS '1 day' OVER (ORDER BY sale_date)
ORDER BY ts;

-- TS_LAST_VALUE 使用最后已知值填充
SELECT ts::DATE AS date, TS_LAST_VALUE(amount) AS filled_amount
FROM daily_sales
TIMESERIES ts AS '1 day' OVER (ORDER BY sale_date)
ORDER BY ts;

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

-- 注意：Vertica 的日期序列生成方式见上述特有语法
-- 注意：使用 COALESCE 进行空值替换
-- 注意：COUNT 分组法是模拟 IGNORE NULLS 的通用方案
