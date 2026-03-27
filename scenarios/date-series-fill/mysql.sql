-- MySQL: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] MySQL Reference Manual - WITH (CTE)
--       https://dev.mysql.com/doc/refman/8.0/en/with.html
--   [2] MySQL Reference Manual - Date and Time Functions
--       https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    DECIMAL(10,2)
);
INSERT INTO daily_sales (sale_date, amount) VALUES
    ('2024-01-01', 100), ('2024-01-02', 150),
    ('2024-01-04', 200), ('2024-01-05', 120),
    ('2024-01-08', 300), ('2024-01-09', 250),
    ('2024-01-10', 180);

-- ============================================================
-- 1. 使用递归 CTE 生成日期序列（MySQL 8.0+）
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT d AS date FROM date_series;

-- 按月生成
WITH RECURSIVE month_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 MONTH FROM month_series WHERE d < '2024-12-01'
)
SELECT d AS month_start FROM month_series;

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT
    ds2.d                      AS date,
    COALESCE(ds.amount, 0)     AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 3. COALESCE 填零 + 累计和
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT
    ds2.d                      AS date,
    COALESCE(ds.amount, 0)     AS amount,
    SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 4. 用最近已知值填充
-- ============================================================

-- MySQL 8.0 不支持 LAG IGNORE NULLS，需要模拟
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds2.d AS date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY ds2.d) AS grp
    FROM date_series ds2
    LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
)
SELECT date,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled ORDER BY date;

-- ============================================================
-- 5. 动态日期范围
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 6. 多维度日期填充
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-04'
),
categories AS (
    SELECT DISTINCT category FROM category_sales
)
SELECT ds.d AS date, c.category, COALESCE(cs.amount, 0) AS amount
FROM date_series ds
CROSS JOIN categories c
LEFT JOIN category_sales cs ON cs.sale_date = ds.d AND cs.category = c.category
ORDER BY c.category, ds.d;

-- 注意：递归 CTE 需要 MySQL 8.0+
-- 注意：MySQL 默认递归深度 1000（cte_max_recursion_depth）
-- 注意：MySQL 不支持 IGNORE NULLS
-- 注意：MySQL 5.x 需使用辅助数字表生成日期序列
