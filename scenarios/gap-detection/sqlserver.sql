-- SQL Server: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Microsoft Docs - Window Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql
--   [2] Microsoft Docs - WITH common_table_expression
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql
--   [3] Itzik Ben-Gan - Gaps and Islands (T-SQL 经典)

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (
    id    INT PRIMARY KEY,
    info  NVARCHAR(100)
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
-- 1. 使用 LAG/LEAD 窗口函数查找数值间隙（SQL Server 2012+）
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
-- 2. 查找日期间隙
-- ============================================================

SELECT
    sale_date                                  AS last_date,
    next_date                                  AS next_date,
    DATEDIFF(DAY, sale_date, next_date) - 1    AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t
WHERE DATEDIFF(DAY, sale_date, next_date) > 1;

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
           DATEADD(DAY,
               -ROW_NUMBER() OVER (ORDER BY sale_date),
               sale_date) AS grp
    FROM daily_sales
) t
GROUP BY grp
ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法（SQL Server 2005+ 兼容）
-- ============================================================

SELECT
    a.id + 1 AS gap_start,
    MIN(b.id) - 1 AS gap_end
FROM orders a
INNER JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;

-- ============================================================
-- 5. 使用递归 CTE 或数字表生成序列
-- ============================================================

-- 递归 CTE（SQL Server 2005+）
WITH seq AS (
    SELECT MIN(id) AS n FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s
LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL
ORDER BY s.n
OPTION (MAXRECURSION 10000);

-- 数字表方法（高效，适合大范围）
;WITH E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1
                UNION ALL SELECT 1 UNION ALL SELECT 1),
     E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
     E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
     nums(n) AS (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM E4)
SELECT n AS missing_id
FROM nums
WHERE n BETWEEN (SELECT MIN(id) FROM orders) AND (SELECT MAX(id) FROM orders)
  AND n NOT IN (SELECT id FROM orders)
ORDER BY n;

-- 日期序列
WITH date_seq AS (
    SELECT CAST(MIN(sale_date) AS DATE) AS d FROM daily_sales
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_seq
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT d AS missing_date
FROM date_seq
LEFT JOIN daily_sales ds ON ds.sale_date = date_seq.d
WHERE ds.sale_date IS NULL
ORDER BY d;

-- ============================================================
-- 6. 综合示例 —— Itzik Ben-Gan 经典 Gaps and Islands 方法
-- ============================================================

-- 间隙 (Gaps)
WITH C AS (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM orders
)
SELECT cur.id + 1 AS gap_start,
       nxt.id - 1 AS gap_end
FROM C cur
JOIN C nxt ON nxt.rn = cur.rn + 1
WHERE nxt.id - cur.id > 1;

-- 岛屿 (Islands)
WITH C AS (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
)
SELECT MIN(id) AS island_start,
       MAX(id) AS island_end,
       MAX(id) - MIN(id) + 1 AS island_size
FROM C
GROUP BY grp
ORDER BY island_start;

-- 注意：LAG/LEAD 需要 SQL Server 2012+
-- 注意：递归 CTE 默认最大递归深度 100，用 OPTION (MAXRECURSION N) 调整
-- 注意：数字表交叉连接方法效率优于递归 CTE
-- 注意：DATEDIFF 用于日期差值计算
