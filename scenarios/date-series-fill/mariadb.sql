-- MariaDB: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] MariaDB Documentation - Recursive CTEs
--       https://mariadb.com/kb/en/recursive-common-table-expressions-overview/
--   [2] MariaDB Documentation - Sequence Engine (seq_1_to_N)
--       https://mariadb.com/kb/en/sequence-storage-engine/

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. 使用 seq_1_to_N 序列引擎（MariaDB 10.3+ 特有）
-- ============================================================

SELECT DATE_ADD('2024-01-01', INTERVAL seq - 1 DAY) AS d
FROM seq_1_to_10;

-- 动态范围
SELECT DATE_ADD(
    (SELECT MIN(sale_date) FROM daily_sales),
    INTERVAL seq - 1 DAY
) AS d
FROM seq_1_to_365
WHERE DATE_ADD(
    (SELECT MIN(sale_date) FROM daily_sales),
    INTERVAL seq - 1 DAY
) <= (SELECT MAX(sale_date) FROM daily_sales);

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

SELECT DATE_ADD('2024-01-01', INTERVAL seq - 1 DAY) AS date,
       COALESCE(ds.amount, 0) AS amount
FROM seq_1_to_10 s
LEFT JOIN daily_sales ds ON ds.sale_date = DATE_ADD('2024-01-01', INTERVAL seq - 1 DAY)
ORDER BY date;

-- ============================================================
-- 3. 递归 CTE 方法（MariaDB 10.2+）
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- ============================================================
-- 4. 用最近已知值填充
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds2.d, ds.amount, COUNT(ds.amount) OVER (ORDER BY ds2.d) AS grp
    FROM date_series ds2 LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
)
SELECT d AS date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM filled ORDER BY d;

-- ============================================================
-- 5-6. 多维度填充
-- ============================================================

-- 使用 seq_1_to_N CROSS JOIN 类别维度
-- SELECT DATE_ADD('2024-01-01', INTERVAL seq - 1 DAY) AS date, c.category, ...
-- FROM seq_1_to_4 CROSS JOIN (SELECT DISTINCT category FROM ...) c ...

-- 注意：seq_1_to_N 序列引擎是 MariaDB 10.3+ 的特有功能
-- 注意：递归 CTE 需要 MariaDB 10.2+
-- 注意：MariaDB 不支持 IGNORE NULLS
-- 注意：seq_1_to_N 比递归 CTE 更高效
