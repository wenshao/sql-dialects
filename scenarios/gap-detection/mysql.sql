-- MySQL: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] MySQL Reference Manual - Window Functions
--       https://dev.mysql.com/doc/refman/8.0/en/window-functions.html
--   [2] MySQL Reference Manual - WITH (Common Table Expressions)
--       https://dev.mysql.com/doc/refman/8.0/en/with.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (
    id    INT PRIMARY KEY,
    info  VARCHAR(100)
);
INSERT INTO orders (id, info) VALUES
    (1, 'a'), (2, 'b'), (3, 'c'),
    (5, 'e'), (6, 'f'),
    (10, 'j'), (11, 'k'), (12, 'l'),
    (15, 'o');

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
-- 1. 使用 LAG/LEAD 窗口函数查找数值间隙（MySQL 8.0+）
-- ============================================================

SELECT
    id            AS gap_start_after,
    next_id       AS gap_end_before,
    next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
) t
WHERE next_id - id > 1;

-- ============================================================
-- 2. 使用 LAG/LEAD 查找日期间隙（MySQL 8.0+）
-- ============================================================

SELECT
    sale_date                                          AS last_date,
    next_date                                          AS next_date,
    DATEDIFF(next_date, sale_date) - 1                 AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t
WHERE DATEDIFF(next_date, sale_date) > 1;

-- ============================================================
-- 3. 岛屿问题 —— 找出连续范围
-- ============================================================

SELECT
    MIN(id) AS island_start,
    MAX(id) AS island_end,
    COUNT(*) AS island_size
FROM (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
) t
GROUP BY grp
ORDER BY island_start;

-- 日期岛屿
SELECT
    MIN(sale_date) AS island_start,
    MAX(sale_date) AS island_end,
    COUNT(*)       AS island_days
FROM (
    SELECT sale_date,
           DATEDIFF(sale_date, '1970-01-01')
             - ROW_NUMBER() OVER (ORDER BY sale_date) AS grp
    FROM daily_sales
) t
GROUP BY grp
ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法（MySQL 5.x 兼容，无需窗口函数）
-- ============================================================

SELECT
    a.id + 1 AS gap_start,
    (SELECT MIN(b.id) FROM orders b WHERE b.id > a.id) - 1 AS gap_end
FROM orders a
WHERE NOT EXISTS (
    SELECT 1 FROM orders c WHERE c.id = a.id + 1
)
AND a.id < (SELECT MAX(id) FROM orders)
ORDER BY gap_start;

-- 使用用户变量（MySQL 5.x 兼容，已弃用方式）
-- SELECT @prev := -1;
-- SELECT gap_start, gap_end FROM (
--     SELECT @prev + 1 AS gap_start, id - 1 AS gap_end, @prev := id
--     FROM orders ORDER BY id
-- ) t WHERE gap_start <= gap_end;

-- ============================================================
-- 5. 使用递归 CTE 生成序列（MySQL 8.0+）
-- ============================================================

WITH RECURSIVE seq AS (
    SELECT MIN(id) AS n FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s
LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL
ORDER BY s.n;

-- 生成日期序列并查找缺失日期
WITH RECURSIVE date_seq AS (
    SELECT MIN(sale_date) AS d FROM daily_sales
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM date_seq
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT d AS missing_date
FROM date_seq
LEFT JOIN daily_sales ds ON ds.sale_date = date_seq.d
WHERE ds.sale_date IS NULL
ORDER BY d;

-- ============================================================
-- 6. 综合示例 —— 同时输出间隙和岛屿
-- ============================================================

WITH ordered AS (
    SELECT id,
           LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
),
islands AS (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
)
SELECT 'Island' AS type,
       MIN(id)  AS range_start,
       MAX(id)  AS range_end,
       COUNT(*) AS size
FROM islands
GROUP BY grp
UNION ALL
SELECT 'Gap',
       id + 1,
       next_id - 1,
       next_id - id - 1
FROM ordered
WHERE next_id - id > 1
ORDER BY range_start;

-- 注意：窗口函数需要 MySQL 8.0+
-- 注意：递归 CTE 需要 MySQL 8.0+
-- 注意：MySQL 5.x 需使用自连接或用户变量方法
-- 注意：MySQL 默认递归 CTE 深度限制为 1000（cte_max_recursion_depth）
