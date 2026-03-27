-- ksqlDB: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] ksqlDB Documentation
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/

-- ============================================================
-- 准备数据
-- ============================================================

-- CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 生成日期序列
-- ============================================================

-- ksqlDB 是流处理引擎，不支持传统的日期序列生成
-- 使用 Kafka Connect 或外部系统生成日期维度数据
-- 然后在 ksqlDB 中作为 TABLE 使用

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

-- 注意：ksqlDB 的日期序列生成方式见上述代码
-- 注意：使用 COALESCE 将缺失值替换为 0
-- 注意：COUNT 分组法是通用的 IGNORE NULLS 模拟方案
