-- Apache Impala: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Impala Documentation - Analytic Functions
--       https://impala.apache.org/docs/build/html/topics/impala_analytic_functions.html
--   [2] Impala Documentation - SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INT, info STRING);
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date TIMESTAMP, amount DECIMAL(10,2));

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙（Impala 2.0+）
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date,
       DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(next_date, sale_date) > 1;

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
-- 5. Impala 的序列生成限制
-- ============================================================

-- Impala 不支持递归 CTE 和 generate_series
-- 使用辅助数字表
-- CREATE TABLE numbers AS SELECT row_number() OVER (ORDER BY 1) AS n
-- FROM large_existing_table LIMIT 10000;
--
-- SELECT n AS missing_id FROM numbers
-- WHERE n BETWEEN (SELECT MIN(id) FROM orders) AND (SELECT MAX(id) FROM orders)
--   AND n NOT IN (SELECT id FROM orders);

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

-- 注意：Impala 从 2.0 版本开始支持分析函数
-- 注意：Impala 不支持递归 CTE
-- 注意：Impala 不支持 generate_series，需使用辅助表
-- 注意：Impala 适合大规模数据的间隙分析（MPP 架构）
