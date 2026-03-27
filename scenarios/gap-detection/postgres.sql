-- PostgreSQL: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/functions-window.html

-- ============================================================
-- 1. LAG/LEAD 查找间隙
-- ============================================================

-- 数值间隙
SELECT id AS gap_after, next_id AS gap_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

-- 日期间隙
SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
      FROM daily_sales) t
WHERE next_date - sale_date > 1;

-- ============================================================
-- 2. 岛屿问题: row_number 差值法
-- ============================================================

-- 连续 ID 范围
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;

-- 连续日期范围
SELECT MIN(sale_date) AS start, MAX(sale_date) AS end, COUNT(*) AS days
FROM (SELECT sale_date,
             sale_date - (ROW_NUMBER() OVER (ORDER BY sale_date))::INT AS grp
      FROM daily_sales) t
GROUP BY grp ORDER BY start;

-- 设计分析: row_number 差值法
--   对连续值序列: value - ROW_NUMBER() 在连续段内是常数。
--   一旦有间隙，差值跳变→不同的 grp 值→GROUP BY 分段。
--   这是经典的 SQL 解法，所有支持窗口函数的数据库都可用。

-- ============================================================
-- 3. generate_series 查找缺失值（PostgreSQL 特有）
-- ============================================================

-- 缺失 ID
SELECT s.id AS missing_id
FROM generate_series((SELECT MIN(id) FROM orders), (SELECT MAX(id) FROM orders)) AS s(id)
LEFT JOIN orders o ON o.id = s.id
WHERE o.id IS NULL;

-- 缺失日期
SELECT s.d::DATE AS missing_date
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales), '1 day'
) AS s(d)
LEFT JOIN daily_sales ds ON ds.sale_date = s.d::DATE
WHERE ds.sale_date IS NULL;

-- 对比:
--   PostgreSQL: generate_series 直接生成完整序列 LEFT JOIN
--   MySQL:      需递归 CTE 或辅助数字表
--   Oracle:     CONNECT BY LEVEL

-- ============================================================
-- 4. 综合: 间隙 + 岛屿 一起输出
-- ============================================================

WITH ordered AS (
    SELECT id, LAG(id) OVER (ORDER BY id) AS prev, LEAD(id) OVER (ORDER BY id) AS next
    FROM orders
),
islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next - 1, next - id - 1
FROM ordered WHERE next - id > 1
ORDER BY range_start;

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================

-- (1) generate_series 让间隙检测变成简单的 LEFT JOIN:
--     不需要窗口函数，不需要自连接。直接生成完整序列比较即可。
--
-- (2) row_number 差值法是纯 SQL 的经典算法:
--     任何支持窗口函数的引擎都能用，不依赖特定函数。
--     原理简洁但不直观——值得在文档中作为标准模式推荐。
