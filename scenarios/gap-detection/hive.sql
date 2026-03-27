-- Hive: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Apache Hive Documentation - Window Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics
--   [2] Apache Hive Documentation - Operators and UDFs
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE orders (id INT, info STRING);
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE, amount DECIMAL(10,2));

-- ============================================================
-- 1. 使用 LAG/LEAD 查找数值间隙（Hive 0.11+）
-- ============================================================

SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) t WHERE next_id - id > 1;

-- ============================================================
-- 2. 查找日期间隙
-- ============================================================

SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(next_date, sale_date) > 1;

-- ============================================================
-- 3. 岛屿问题
-- ============================================================

SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) t GROUP BY grp ORDER BY island_start;

-- ============================================================
-- 4. 自连接方法
-- ============================================================

SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

-- ============================================================
-- 5. 使用 LATERAL VIEW + posexplode 生成序列
-- ============================================================

-- Hive 没有 generate_series，使用 posexplode 或辅助表
-- 方法1: 使用 LATERAL VIEW posexplode + split
SELECT pos + (SELECT MIN(id) FROM orders) AS missing_id
FROM (SELECT 1) dummy
LATERAL VIEW posexplode(split(space(
    (SELECT MAX(id) - MIN(id) FROM orders)
), ' ')) t AS pos, val
WHERE pos + (SELECT MIN(id) FROM orders) NOT IN (SELECT id FROM orders);

-- 方法2: 使用数字辅助表
-- CREATE TABLE numbers (n INT);
-- INSERT INTO numbers SELECT ROW_NUMBER() OVER () FROM large_table LIMIT 10000;

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

-- 注意：Hive 窗口函数从 0.11 版本开始支持
-- 注意：Hive 不支持递归 CTE
-- 注意：Hive 没有 generate_series，需用替代方法
-- 注意：posexplode + split(space(n)) 是常见的序列生成技巧
