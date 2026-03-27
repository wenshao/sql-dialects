-- Oracle: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html
--   [2] Oracle Documentation - CONNECT BY
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Hierarchical-Queries.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (
    id    NUMBER(10) PRIMARY KEY,
    info  VARCHAR2(100)
);
INSERT ALL
    INTO orders VALUES (1, 'a') INTO orders VALUES (2, 'b')
    INTO orders VALUES (3, 'c') INTO orders VALUES (5, 'e')
    INTO orders VALUES (6, 'f') INTO orders VALUES (10, 'j')
    INTO orders VALUES (11, 'k') INTO orders VALUES (12, 'l')
    INTO orders VALUES (15, 'o')
SELECT 1 FROM DUAL;

CREATE TABLE daily_sales (
    sale_date DATE PRIMARY KEY,
    amount    NUMBER(10,2)
);
INSERT ALL
    INTO daily_sales VALUES (DATE '2024-01-01', 100)
    INTO daily_sales VALUES (DATE '2024-01-02', 150)
    INTO daily_sales VALUES (DATE '2024-01-04', 200)
    INTO daily_sales VALUES (DATE '2024-01-05', 120)
    INTO daily_sales VALUES (DATE '2024-01-08', 300)
    INTO daily_sales VALUES (DATE '2024-01-09', 250)
    INTO daily_sales VALUES (DATE '2024-01-10', 180)
SELECT 1 FROM DUAL;

-- ============================================================
-- 1. 使用 LAG/LEAD 窗口函数查找数值间隙
-- ============================================================

SELECT
    id            AS gap_start_after,
    next_id       AS gap_end_before,
    next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
)
WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT
    sale_date                          AS last_date,
    next_date                          AS next_date,
    next_date - sale_date - 1          AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
)
WHERE next_date - sale_date > 1;

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
)
GROUP BY grp
ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法（兼容 Oracle 8i 以上）
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
-- 5. 使用 CONNECT BY LEVEL 生成序列（Oracle 特有）
-- ============================================================

-- 生成数值序列找缺失 id
SELECT lvl AS missing_id
FROM (
    SELECT LEVEL + (SELECT MIN(id) - 1 FROM orders) AS lvl
    FROM DUAL
    CONNECT BY LEVEL <= (SELECT MAX(id) - MIN(id) + 1 FROM orders)
) seq
LEFT JOIN orders o ON o.id = seq.lvl
WHERE o.id IS NULL
ORDER BY lvl;

-- 生成日期序列找缺失日期
SELECT (SELECT MIN(sale_date) FROM daily_sales) + LEVEL - 1 AS missing_date
FROM DUAL
CONNECT BY LEVEL <= (SELECT MAX(sale_date) - MIN(sale_date) + 1 FROM daily_sales)
MINUS
SELECT sale_date FROM daily_sales
ORDER BY 1;

-- 递归 CTE 方法（Oracle 11gR2+）
WITH seq (n) AS (
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
-- 6. Tabibitosan 方法（日本式间隙与岛屿方法）
-- ============================================================

-- 岛屿
SELECT MIN(id) AS island_start,
       MAX(id) AS island_end,
       COUNT(*) AS island_size
FROM (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
)
GROUP BY grp
ORDER BY island_start;

-- 间隙
SELECT prev_id + 1 AS gap_start,
       id - 1      AS gap_end,
       id - prev_id - 1 AS gap_size
FROM (
    SELECT id, LAG(id) OVER (ORDER BY id) AS prev_id
    FROM orders
)
WHERE id - prev_id > 1;

-- 注意：CONNECT BY LEVEL 是 Oracle 特有的序列生成方式
-- 注意：LAG/LEAD 分析函数从 Oracle 8i 开始支持
-- 注意：递归 CTE (WITH RECURSIVE) 从 Oracle 11gR2 开始支持
-- 注意：Oracle 日期相减直接得到天数（数值型）
