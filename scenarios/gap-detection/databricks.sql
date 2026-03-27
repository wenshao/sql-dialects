-- Databricks SQL: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Databricks SQL Reference - Window Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html#window-functions
--   [2] Databricks SQL Reference - sequence
--       https://docs.databricks.com/en/sql/language-manual/functions/sequence.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TEMPORARY VIEW orders AS
SELECT * FROM VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o') AS t(id, info);

CREATE TEMPORARY VIEW daily_sales AS
SELECT * FROM VALUES
    (DATE '2024-01-01', 100),(DATE '2024-01-02', 150),(DATE '2024-01-04', 200),
    (DATE '2024-01-05', 120),(DATE '2024-01-08', 300),(DATE '2024-01-09', 250),
    (DATE '2024-01-10', 180) AS t(sale_date, amount);

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DATEDIFF(next_date, sale_date) > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders)
GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. 使用 sequence + explode（Databricks 继承 Spark SQL）
-- ============================================================

SELECT col AS missing_id
FROM (SELECT explode(sequence(
    (SELECT MIN(id) FROM orders), (SELECT MAX(id) FROM orders)
)) AS col)
LEFT JOIN orders o ON o.id = col
WHERE o.id IS NULL ORDER BY col;

SELECT col AS missing_date
FROM (SELECT explode(sequence(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
)) AS col)
LEFT JOIN daily_sales ds ON ds.sale_date = col
WHERE ds.sale_date IS NULL ORDER BY col;

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

-- 注意：Databricks SQL 基于 Spark SQL，语法高度兼容
-- 注意：sequence + explode 是 Databricks 中常用的序列生成方式
-- 注意：Databricks SQL 不支持递归 CTE
