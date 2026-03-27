-- DamengDB (达梦): 日期序列生成与间隙填充 (Date Series Fill)
--
-- 参考资料:
--   [1] DamengDB (达梦) Documentation - SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-dataquery.html
--   [2] DamengDB (达梦) Documentation - Functions
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-function.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);

-- ============================================================
-- 1. 使用 CONNECT BY / 递归 CTE 生成日期序列
-- ============================================================

-- Oracle 模式：CONNECT BY LEVEL
-- SELECT DATE '2024-01-01' + LEVEL - 1 AS d
-- FROM DUAL CONNECT BY LEVEL <= 10;

-- MySQL 模式：递归 CTE
WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT d FROM date_series;

-- ============================================================
-- 2. LEFT JOIN 填充间隙
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
-- 3. COALESCE 填零 + 累计和
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT DATE '2024-01-01' AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series WHERE d < '2024-01-10'
)
SELECT ds2.d, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY ds2.d) AS running_total
FROM date_series ds2
LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- ============================================================
-- 4. 用最近已知值填充（Oracle 模式支持 IGNORE NULLS）
-- ============================================================

-- Oracle 模式：LAST_VALUE(amount IGNORE NULLS) OVER (...)
-- MySQL 模式：用 COUNT 分组法模拟

-- ============================================================
-- 5-6. 动态范围 + 多维度
-- ============================================================

WITH RECURSIVE date_series AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_series
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT ds2.d, COALESCE(ds.amount, 0) AS amount
FROM date_series ds2 LEFT JOIN daily_sales ds ON ds.sale_date = ds2.d ORDER BY ds2.d;

-- 注意：DamengDB (达梦) 支持 MySQL 和 Oracle 两种模式
-- 注意：Oracle 模式使用 CONNECT BY LEVEL 生成序列
-- 注意：Oracle 模式支持 IGNORE NULLS
-- 注意：MySQL 模式使用递归 CTE
