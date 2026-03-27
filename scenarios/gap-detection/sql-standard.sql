-- SQL Standard: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] ISO/IEC 9075 SQL Standard - Window Functions (SQL:2003)
--   [2] ISO/IEC 9075 SQL Standard - WITH RECURSIVE (SQL:1999)

-- ============================================================
-- 准备数据（标准 SQL）
-- ============================================================

CREATE TABLE orders (
    id    INTEGER PRIMARY KEY,
    info  VARCHAR(100)
);

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    DECIMAL(10,2)
);

-- ============================================================
-- 1. 使用 LAG/LEAD 窗口函数查找数值间隙（SQL:2003）
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
-- 2. 使用 LAG/LEAD 查找日期间隙
-- ============================================================

-- 标准 SQL 没有统一的日期差值函数
-- 不同数据库需要使用各自的日期差值方法

-- ============================================================
-- 3. 岛屿问题 —— row_number 差值法（SQL:2003）
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

-- ============================================================
-- 4. 自连接方法（SQL-92 兼容）
-- ============================================================

SELECT
    a.id + 1 AS gap_start,
    MIN(b.id) - 1 AS gap_end
FROM orders a
JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;

-- ============================================================
-- 5. 使用递归 CTE 生成序列（SQL:1999）
-- ============================================================

WITH RECURSIVE seq(n) AS (
    SELECT MIN(id) FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s
LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL
ORDER BY s.n;

-- ============================================================
-- 6. 综合示例
-- ============================================================

WITH ordered AS (
    SELECT id,
           LAG(id)  OVER (ORDER BY id) AS prev_id,
           LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
)
SELECT 'Gap'     AS type,
       id + 1    AS range_start,
       next_id - 1 AS range_end,
       next_id - id - 1 AS size
FROM ordered
WHERE next_id - id > 1
ORDER BY range_start;

-- 注意：LAG/LEAD 是 SQL:2003 标准的窗口函数
-- 注意：WITH RECURSIVE 是 SQL:1999 标准
-- 注意：自连接方法兼容 SQL-92 标准
-- 注意：日期运算在标准 SQL 中没有统一的 DATEDIFF 函数
