-- Apache Impala: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Apache Impala Documentation
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html

-- ============================================================
-- 准备数据
-- ============================================================

-- CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 生成日期序列
-- ============================================================

-- Impala 不支持 generate_series 和递归 CTE
-- 使用辅助数字表生成日期序列
-- CREATE TABLE numbers AS SELECT row_number() OVER (ORDER BY 1) - 1 AS n
-- FROM large_table LIMIT 10000;
-- SELECT DATE_ADD('2024-01-01', n) AS d FROM numbers WHERE n < 10;

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

-- 注意：Apache Impala 的日期序列生成方式见上述代码
-- 注意：使用 COALESCE 将缺失值替换为 0
-- 注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
