-- SQL Server: 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] Microsoft Docs - Recursive CTEs
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql
--   [2] Microsoft Docs - Date Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/date-and-time-data-types-and-functions-transact-sql

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. 递归 CTE 生成日期序列
-- ============================================================

WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT d AS date FROM date_series;

-- 数字表方法（高效，适合大范围）
;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1),
     E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
     E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
     nums(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 FROM E4)
SELECT DATEADD(DAY, n, '2024-01-01') AS d
FROM nums WHERE n <= DATEDIFF(DAY, '2024-01-01', '2024-01-10');

-- ============================================================
-- 2. LEFT JOIN 填充间隙
-- ============================================================

WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, ISNULL(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 3. ISNULL/COALESCE 填零 + 累计和
-- ============================================================

WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date, ISNULL(ds.amount, 0) AS amount,
       SUM(ISNULL(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- ============================================================
-- 4. 用最近已知值填充（SQL Server 2022+ 支持 IGNORE NULLS）
-- ============================================================

-- SQL Server 2022+ 支持 IGNORE NULLS
WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d AS date,
       LAST_VALUE(ds.amount) IGNORE NULLS
           OVER (ORDER BY ds2.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d;

-- 兼容旧版本的方法
WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds2.d, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY ds2.d) AS grp
    FROM date_series ds2
    LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
)
SELECT d AS date,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM filled ORDER BY d;

-- ============================================================
-- 5-6. 动态日期范围 + 多维度
-- ============================================================

WITH date_series AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds2.d, ISNULL(ds.amount, 0) AS amount
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d
ORDER BY ds2.d
OPTION (MAXRECURSION 10000);

-- 注意：递归 CTE 默认最大深度 100，用 OPTION (MAXRECURSION N) 调整
-- 注意：数字表方法性能优于递归 CTE
-- 注意：SQL Server 2022+ 支持 IGNORE NULLS
-- 注意：ISNULL 是 T-SQL 特有，COALESCE 是标准 SQL
