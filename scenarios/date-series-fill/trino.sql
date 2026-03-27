-- Trino: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Trino Documentation
--       https://trino.io/docs/current/functions/array.html#sequence

-- ============================================================
-- 准备数据
-- ============================================================

-- CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 生成日期序列
-- ============================================================

-- 使用 sequence + UNNEST 生成日期序列
SELECT s AS d
FROM UNNEST(sequence(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL '1' DAY
)) AS t(s);

SELECT t.s AS date, COALESCE(ds.amount, 0) AS amount
FROM UNNEST(sequence(DATE '2024-01-01', DATE '2024-01-10', INTERVAL '1' DAY)) AS t(s)
LEFT JOIN daily_sales ds ON ds.sale_date = t.s ORDER BY t.s;

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

-- 注意：Trino 的日期序列生成方式见上述代码
-- 注意：使用 COALESCE 将缺失值替换为 0
-- 注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
