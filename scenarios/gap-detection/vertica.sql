-- Vertica: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Vertica Documentation - Analytic Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/AnalyticFunctions.htm
--   [2] Vertica Documentation - Time Series Analytics
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/TimeSeries/TimeSeriesFunctions.htm

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INT PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date, DATEDIFF('DAY', sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF('DAY', sale_date, next_date) > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. Vertica 时间序列函数 TS_FIRST_VALUE / TS_LAST_VALUE
-- ============================================================

-- 使用 Vertica 的 TIMESERIES 子句（Vertica 特有）
-- TIMESERIES 自动填充时间间隙
SELECT ts::DATE AS all_date,
       TS_FIRST_VALUE(amount) AS amount
FROM daily_sales
TIMESERIES ts AS '1 day' OVER (ORDER BY sale_date)
ORDER BY ts;

-- 传统方法：使用递归 CTE 生成序列
WITH seq AS (
    SELECT MIN(id) AS n FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;

-- ============================================================
-- 6. 综合示例
-- ============================================================

WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY range_start;

-- 注意：Vertica 的 TIMESERIES 子句是时间间隙填充的专用功能
-- 注意：TS_FIRST_VALUE / TS_LAST_VALUE 配合 TIMESERIES 使用
-- 注意：Vertica 列式存储对窗口函数有很好的优化
