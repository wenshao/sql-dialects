-- MaxCompute (ODPS): 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] MaxCompute (ODPS) Documentation
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/overview-of-sql-statements

-- ============================================================
-- 准备数据
-- ============================================================

-- CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 生成日期序列
-- ============================================================

-- 使用 posexplode + split(space(n)) 生成日期序列
SELECT DATE_ADD('2024-01-01', pos) AS d
FROM (SELECT 1) dummy
LATERAL VIEW posexplode(split(space(9), ' ')) t AS pos, val;

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

-- 注意：MaxCompute (ODPS) 的日期序列生成方式见上述代码
-- 注意：使用 COALESCE 将缺失值替换为 0
-- 注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
