-- SQL Server: 日期序列生成与间隙填充
--
-- 参考资料:
--   [1] SQL Server - Recursive CTEs
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql

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
;WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT d AS date FROM date_series;
-- 默认最大递归 100，超过需要 OPTION (MAXRECURSION N)

-- ============================================================
-- 2. 数字表方法（性能更优，适合大范围）
-- ============================================================

-- SQL Server 没有 generate_series() 函数（PostgreSQL 有）。
-- 经典替代: 交叉连接生成数字表
;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1),
     E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),      -- 100
     E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),      -- 10000
     nums(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 FROM E4)
SELECT DATEADD(DAY, n, '2024-01-01') AS d
FROM nums WHERE n <= DATEDIFF(DAY, '2024-01-01', '2024-01-10');

-- 设计分析（对引擎开发者）:
--   SQL Server 缺少 generate_series() 是一个重要缺失。
--   PostgreSQL: generate_series('2024-01-01'::date, '2024-01-10', '1 day')
--   MySQL:      递归 CTE（同 SQL Server）
--   数字表方法是 SQL Server 社区发明的经典 hack——利用 CROSS JOIN 指数增长。

-- ============================================================
-- 3. LEFT JOIN 填充间隙
-- ============================================================
;WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds.d AS date, ISNULL(s.amount, 0) AS amount
FROM date_series ds
LEFT JOIN daily_sales s ON s.sale_date = ds.d
ORDER BY ds.d;

-- ============================================================
-- 4. 填充 + 累计和
-- ============================================================
;WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds.d AS date, ISNULL(s.amount, 0) AS amount,
       SUM(ISNULL(s.amount, 0)) OVER (ORDER BY ds.d) AS running_total
FROM date_series ds
LEFT JOIN daily_sales s ON s.sale_date = ds.d ORDER BY ds.d;

-- ============================================================
-- 5. 用最近已知值填充（Forward Fill）
-- ============================================================

-- 2022+: IGNORE NULLS（最简洁）
;WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
)
SELECT ds.d,
       LAST_VALUE(s.amount) IGNORE NULLS
           OVER (ORDER BY ds.d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
           AS filled_amount
FROM date_series ds LEFT JOIN daily_sales s ON s.sale_date = ds.d;

-- 兼容旧版本: 分组填充法
;WITH date_series AS (
    SELECT CAST('2024-01-01' AS DATE) AS d UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series WHERE d < '2024-01-10'
),
filled AS (
    SELECT ds.d, s.amount,
           COUNT(s.amount) OVER (ORDER BY ds.d) AS grp
    FROM date_series ds LEFT JOIN daily_sales s ON s.sale_date = ds.d
)
SELECT d, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM filled ORDER BY d;

-- ============================================================
-- 6. 动态日期范围
-- ============================================================
;WITH date_series AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds.d, ISNULL(s.amount, 0) AS amount
FROM date_series ds LEFT JOIN daily_sales s ON s.sale_date = ds.d
ORDER BY ds.d OPTION (MAXRECURSION 10000);

-- 注意: ISNULL 是 T-SQL 特有，COALESCE 是标准 SQL
-- 注意: 2022+ 支持 IGNORE NULLS
-- 注意: 数字表方法性能优于递归 CTE（避免递归开销）
