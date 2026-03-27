-- BigQuery: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] BigQuery Documentation - GENERATE_DATE_ARRAY
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/array_functions#generate_date_array
--   [2] BigQuery Documentation - GENERATE_TIMESTAMP_ARRAY
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/array_functions#generate_timestamp_array

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TEMP TABLE daily_sales AS
SELECT * FROM UNNEST([
    STRUCT(DATE '2024-01-01' AS sale_date, 100.0 AS amount),
    (DATE '2024-01-02', 150), (DATE '2024-01-04', 200),
    (DATE '2024-01-05', 120), (DATE '2024-01-08', 300),
    (DATE '2024-01-09', 250), (DATE '2024-01-10', 180)
]);

-- ============================================================
-- 1. GENERATE_DATE_ARRAY 生成日期序列（BigQuery 特有）
-- ============================================================

SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d;

-- 按月
SELECT d FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-12-01', INTERVAL 1 MONTH
)) AS d;

-- 时间戳序列
SELECT ts FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
    TIMESTAMP '2024-01-01 00:00:00',
    TIMESTAMP '2024-01-01 23:00:00',
    INTERVAL 1 HOUR
)) AS ts;

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

SELECT d AS date, COALESCE(ds.amount, 0) AS amount
FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d
ORDER BY d;

-- ============================================================
-- 3. COALESCE 填零 + 累计和
-- ============================================================

SELECT d AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d
ORDER BY d;

-- ============================================================
-- 4. 用最近已知值填充（BigQuery 支持 IGNORE NULLS）
-- ============================================================

SELECT d AS date,
       LAST_VALUE(ds.amount IGNORE NULLS)
           OVER (ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM UNNEST(GENERATE_DATE_ARRAY(
    DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY
)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d
ORDER BY d;

-- ============================================================
-- 5. 动态日期范围
-- ============================================================

SELECT d AS date, COALESCE(ds.amount, 0) AS amount
FROM UNNEST(GENERATE_DATE_ARRAY(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
)) AS d
LEFT JOIN daily_sales ds ON ds.sale_date = d
ORDER BY d;

-- ============================================================
-- 6. 多维度日期填充
-- ============================================================

SELECT d AS date, c AS category, COALESCE(cs.amount, 0) AS amount
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2024-01-01', DATE '2024-01-04', INTERVAL 1 DAY)) AS d
CROSS JOIN (SELECT DISTINCT category AS c FROM category_sales) cats
LEFT JOIN category_sales cs ON cs.sale_date = d AND cs.category = c
ORDER BY c, d;

-- 注意：GENERATE_DATE_ARRAY / GENERATE_TIMESTAMP_ARRAY 是 BigQuery 特有
-- 注意：BigQuery 原生支持 IGNORE NULLS
-- 注意：UNNEST 用于将数组展开为行
-- 注意：BigQuery 不支持递归 CTE 用于序列生成
