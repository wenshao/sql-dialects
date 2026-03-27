-- DuckDB: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] DuckDB Documentation - generate_series
--       https://duckdb.org/docs/sql/functions/nested#generate_series
--   [2] DuckDB Documentation - Date Functions
--       https://duckdb.org/docs/sql/functions/date

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. generate_series 生成日期序列
-- ============================================================

SELECT d::DATE AS date
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d);

-- range 函数（DuckDB 特有，不包含终点）
SELECT d::DATE AS date
FROM range(DATE '2024-01-01', DATE '2024-01-11', INTERVAL 1 DAY) t(d);

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 3. COALESCE + 累计和
-- ============================================================

SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- ============================================================
-- 4. 用最近已知值填充
-- ============================================================

-- DuckDB 支持某些窗口函数中的 IGNORE NULLS
WITH filled AS (
    SELECT d::DATE AS date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM generate_series(DATE '2024-01-01', DATE '2024-01-10', INTERVAL 1 DAY) t(d)
    LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled ORDER BY date;

-- ============================================================
-- 5-6. 动态范围 + 多维度
-- ============================================================

SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;

-- 注意：DuckDB 原生支持 generate_series（类似 PostgreSQL）
-- 注意：DuckDB 还支持 range 函数（不包含终点）
-- 注意：DuckDB 的日期算术运算非常灵活
-- 注意：DuckDB 列式存储对 LEFT JOIN + 聚合有很好的优化
