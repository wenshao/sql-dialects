-- Hive: 间隙检测与岛屿问题 (Gap Detection & Islands)
--
-- 参考资料:
--   [1] Apache Hive - Window Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics

-- ============================================================
-- 1. LAG/LEAD 检测数值间隙
-- ============================================================
SELECT id AS gap_after, next_id AS gap_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) t WHERE next_id - id > 1;

-- ============================================================
-- 2. 日期间隙检测
-- ============================================================
SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(next_date, sale_date) > 1;

-- ============================================================
-- 3. 岛屿问题: id - ROW_NUMBER 分组法
-- ============================================================
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) t GROUP BY grp ORDER BY island_start;

-- 原理: 连续序列中 id - ROW_NUMBER() 的值相同
-- 例: id={1,2,3,5,6,10} → id-rn={0,0,0,1,1,4} → 三个岛屿

-- ============================================================
-- 4. 综合: 同时展示岛屿和间隙
-- ============================================================
WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS start_val, MAX(id) AS end_val, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY start_val;

-- ============================================================
-- 5. 生成缺失值序列 (POSEXPLODE 技巧)
-- ============================================================
-- Hive 没有 generate_series，使用 POSEXPLODE + SPACE 技巧
SELECT pos + 1 AS missing_id  -- 假设 ID 从 1 开始
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(99), ' ')) t AS pos, val
WHERE pos + 1 NOT IN (SELECT id FROM orders)
  AND pos + 1 <= (SELECT MAX(id) FROM orders);

-- ============================================================
-- 6. 跨引擎对比
-- ============================================================
-- 引擎          间隙检测方法              序列生成
-- MySQL(8.0+)   LAG/LEAD + CTE           递归 CTE
-- PostgreSQL    LAG/LEAD                  generate_series
-- Hive          LAG/LEAD                  POSEXPLODE(SPLIT(SPACE(n)))
-- Spark SQL     LAG/LEAD                  sequence() + explode()
-- BigQuery      LAG/LEAD                  GENERATE_ARRAY

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================
-- 1. LAG/LEAD 是间隙检测的基础: 窗口函数的偏移函数是必备能力
-- 2. id - ROW_NUMBER 是岛屿问题的经典解法: 利用了连续值的数学特性
-- 3. generate_series 是序列生成的基本需求: Hive 的 POSEXPLODE 技巧证明了用户需要此功能
