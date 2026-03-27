-- DuckDB: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] DuckDB Documentation - Window Functions
--       https://duckdb.org/docs/sql/window_functions
--   [2] DuckDB Documentation - generate_series
--       https://duckdb.org/docs/sql/functions/nested#generate_series

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INTEGER PRIMARY KEY, info VARCHAR);
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),
    ('2024-01-10',180);

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE next_date - sale_date > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. 使用 generate_series（DuckDB 原生支持）
-- ============================================================

-- 缺失的 id
SELECT s AS missing_id
FROM generate_series(
    (SELECT MIN(id) FROM orders),
    (SELECT MAX(id) FROM orders)
) t(s)
LEFT JOIN orders o ON o.id = t.s
WHERE o.id IS NULL ORDER BY s;

-- 缺失的日期
SELECT d::DATE AS missing_date
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL 1 DAY
) t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
WHERE ds.sale_date IS NULL ORDER BY d;

-- ============================================================
-- 6. 综合示例 —— 使用 DuckDB 的 QUALIFY 子句
-- ============================================================

-- 使用 QUALIFY 简化间隙查询
SELECT id AS gap_start_after,
       LEAD(id) OVER (ORDER BY id) AS gap_end_before,
       LEAD(id) OVER (ORDER BY id) - id - 1 AS gap_size
FROM orders
QUALIFY LEAD(id) OVER (ORDER BY id) - id > 1;

-- 注意：DuckDB 原生支持 generate_series（类似 PostgreSQL）
-- 注意：DuckDB 支持 QUALIFY 子句过滤窗口函数结果
-- 注意：DuckDB 日期相减直接返回天数差值
