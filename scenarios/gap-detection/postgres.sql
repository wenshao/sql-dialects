-- PostgreSQL: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/functions-window.html
--   [2] PostgreSQL Documentation - generate_series
--       https://www.postgresql.org/docs/current/functions-srf.html
--   [3] PostgreSQL Wiki - Gaps and Islands
--       https://wiki.postgresql.org/wiki/Gap-filling

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (
    id    INTEGER PRIMARY KEY,
    info  TEXT
);
INSERT INTO orders (id, info) VALUES
    (1, 'a'), (2, 'b'), (3, 'c'),
    (5, 'e'), (6, 'f'),
    (10, 'j'), (11, 'k'), (12, 'l'),
    (15, 'o');

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    NUMERIC(10,2)
);
INSERT INTO daily_sales (sale_date, amount) VALUES
    ('2024-01-01', 100), ('2024-01-02', 150),
    ('2024-01-04', 200), ('2024-01-05', 120),
    ('2024-01-08', 300), ('2024-01-09', 250),
    ('2024-01-10', 180);

-- ============================================================
-- 1. 使用 LAG/LEAD 窗口函数查找数值间隙
-- ============================================================

-- 找出 id 序列中缺失的范围
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
-- 2. 使用 LAG/LEAD 查找日期间隙
-- ============================================================

SELECT
    sale_date                          AS last_date,
    next_date                          AS next_date,
    next_date - sale_date - 1          AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t
WHERE next_date - sale_date > 1;

-- ============================================================
-- 3. 岛屿问题 —— 找出连续范围（Islands）
-- ============================================================

-- 方法: row_number 差值法
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

-- 日期序列的岛屿
SELECT
    MIN(sale_date) AS island_start,
    MAX(sale_date) AS island_end,
    COUNT(*)       AS island_days
FROM (
    SELECT sale_date,
           sale_date - (ROW_NUMBER() OVER (ORDER BY sale_date))::INT AS grp
    FROM daily_sales
) t
GROUP BY grp
ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法（适用于不支持窗口函数的场景）
-- ============================================================

-- 找间隙：找到每个 id 之后最近的 id
SELECT
    a.id + 1  AS gap_start,
    MIN(b.id) - 1 AS gap_end
FROM orders a
JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;

-- ============================================================
-- 5. 使用 generate_series 查找缺失值（PostgreSQL 特有）
-- ============================================================

-- 找出缺失的 id
SELECT s.id AS missing_id
FROM generate_series(
    (SELECT MIN(id) FROM orders),
    (SELECT MAX(id) FROM orders)
) AS s(id)
LEFT JOIN orders o ON o.id = s.id
WHERE o.id IS NULL
ORDER BY s.id;

-- 找出缺失的日期
SELECT s.d::DATE AS missing_date
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL '1 day'
) AS s(d)
LEFT JOIN daily_sales ds ON ds.sale_date = s.d::DATE
WHERE ds.sale_date IS NULL
ORDER BY s.d;

-- ============================================================
-- 6. 综合示例 —— 同时输出间隙和岛屿
-- ============================================================

WITH ordered AS (
    SELECT id,
           LAG(id)  OVER (ORDER BY id) AS prev_id,
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

-- 注意：generate_series 是 PostgreSQL 特有函数（9.0+）
-- 注意：窗口函数 LAG/LEAD 需要 PostgreSQL 8.4+
-- 注意：对于大数据集，generate_series 方法内存消耗较大
