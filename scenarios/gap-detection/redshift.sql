-- Amazon Redshift: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Redshift Documentation - Window Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Window_functions.html
--   [2] Redshift Documentation - generate_series
--       https://docs.aws.amazon.com/redshift/latest/dg/r_GENERATE_SERIES.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INT, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));
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

SELECT sale_date, next_date, DATEDIFF(DAY, sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(DAY, sale_date, next_date) > 1;

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
-- 5. 使用 generate_series（Redshift 支持有限的 generate_series）
-- ============================================================

-- 使用递归数字序列（Redshift 不支持 generate_series 用于 FROM）
-- 改用 Redshift 系统表生成序列
WITH seq AS (
    SELECT (ROW_NUMBER() OVER (ORDER BY 1)) AS n
    FROM stl_connection_log LIMIT 10000
)
SELECT s.n AS missing_id
FROM seq s
WHERE s.n BETWEEN (SELECT MIN(id) FROM orders) AND (SELECT MAX(id) FROM orders)
  AND s.n NOT IN (SELECT id FROM orders)
ORDER BY s.n;

-- 日期序列
WITH date_seq AS (
    SELECT DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY 1) - 1,
           (SELECT MIN(sale_date) FROM daily_sales)) AS d
    FROM stl_connection_log LIMIT 10000
)
SELECT d AS missing_date
FROM date_seq
WHERE d <= (SELECT MAX(sale_date) FROM daily_sales)
  AND d NOT IN (SELECT sale_date FROM daily_sales)
ORDER BY d;

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

-- 注意：Redshift 不支持递归 CTE
-- 注意：Redshift 的 generate_series 只能用于数值，不能直接用于 FROM 子句
-- 注意：常用系统表（如 stl_connection_log）作为行源来生成序列
-- 注意：Redshift 基于 PostgreSQL 8.0 分支，语法兼容性有限
