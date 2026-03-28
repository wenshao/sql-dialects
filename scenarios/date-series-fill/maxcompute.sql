-- MaxCompute (ODPS): 日期序列生成与间隙填充
--
-- 参考资料:
--   [1] MaxCompute SQL Reference
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- ============================================================
-- 1. 生成日期序列 —— MaxCompute 没有 generate_series
-- ============================================================

-- MaxCompute/Hive 标准方案: posexplode + split(space(n))
SELECT DATE_ADD(DATE '2024-01-01', pos) AS d
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(9), ' ')) t AS pos, val;
-- 生成 2024-01-01 ~ 2024-01-10（10 天）

-- 原理解析:
--   SPACE(9) = '         '（9 个空格）
--   SPLIT('         ', ' ') = ['', '', '', ..., '']（10 个空字符串元素）
--   POSEXPLODE = 生成 (0,''), (1,''), ..., (9,'')
--   DATE_ADD('2024-01-01', pos) = 偏移 pos 天
-- 这是 Hive 生态没有 generate_series 的经典 workaround

-- 生成更长的序列: 动态计算天数差
SELECT DATE_ADD(DATE '2024-01-01', pos) AS d
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(
    DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'dd')
), ' ')) t AS pos, val;
-- 生成 2024 年全年日期序列（366 天）

-- 对比:
--   PostgreSQL:  generate_series('2024-01-01'::date, '2024-12-31', '1 day')
--   BigQuery:    UNNEST(GENERATE_DATE_ARRAY('2024-01-01', '2024-12-31'))
--   Snowflake:   GENERATOR(ROWCOUNT => 366) + DATEADD
--   MySQL:       递归 CTE（8.0+）或数字辅助表

-- ============================================================
-- 2. 日期间隙填充: COALESCE 填零
-- ============================================================

-- 假设: daily_sales(sale_date DATE, amount DECIMAL(10,2))
-- 目标: 没有销售的日期填充 amount = 0

WITH date_series AS (
    SELECT DATE_ADD(DATE '2024-01-01', pos) AS d
    FROM (SELECT 1) dummy
    LATERAL VIEW POSEXPLODE(SPLIT(SPACE(30), ' ')) t AS pos, val
)
SELECT ds.d AS sale_date,
       COALESCE(s.amount, 0) AS amount
FROM date_series ds
LEFT JOIN daily_sales s ON ds.d = s.sale_date
ORDER BY ds.d;

-- ============================================================
-- 3. 用最近已知值填充（Forward Fill）
-- ============================================================

-- 场景: 股票价格，非交易日用前一个交易日的价格填充
-- MaxCompute 不支持 LAST_VALUE IGNORE NULLS → 需要 workaround

WITH date_series AS (
    SELECT DATE_ADD(DATE '2024-01-01', pos) AS d
    FROM (SELECT 1) dummy
    LATERAL VIEW POSEXPLODE(SPLIT(SPACE(30), ' ')) t AS pos, val
),
joined AS (
    SELECT ds.d, s.amount
    FROM date_series ds
    LEFT JOIN daily_sales s ON ds.d = s.sale_date
),
-- COUNT 分组法: 将连续 NULL 分到同一个分组
grouped AS (
    SELECT d, amount,
           COUNT(amount) OVER (ORDER BY d) AS grp
    FROM joined
)
SELECT d,
       FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY d) AS filled_amount
FROM grouped
ORDER BY d;

-- 原理: COUNT(amount) 只在非 NULL 时递增
--   日期  | amount | grp
--   01-01 | 100    | 1    ← 非 NULL，grp = 1
--   01-02 | NULL   | 1    ← NULL，grp 不变 = 1
--   01-03 | NULL   | 1    ← NULL，grp 不变 = 1
--   01-04 | 200    | 2    ← 非 NULL，grp = 2
--   01-05 | NULL   | 2    ← NULL，grp 不变 = 2
-- PARTITION BY grp + FIRST_VALUE → 每组用第一个非 NULL 值填充

-- ============================================================
-- 4. 累计和填充
-- ============================================================

WITH date_series AS (
    SELECT DATE_ADD(DATE '2024-01-01', pos) AS d
    FROM (SELECT 1) dummy
    LATERAL VIEW POSEXPLODE(SPLIT(SPACE(30), ' ')) t AS pos, val
)
SELECT ds.d,
       COALESCE(s.amount, 0) AS daily_amount,
       SUM(COALESCE(s.amount, 0)) OVER (ORDER BY ds.d) AS running_total
FROM date_series ds
LEFT JOIN daily_sales s ON ds.d = s.sale_date
ORDER BY ds.d;

-- ============================================================
-- 5. 辅助表方案（大规模日期序列）
-- ============================================================

-- 对于生产环境，推荐预创建日期维度表:
CREATE TABLE IF NOT EXISTS dim_date (
    d        DATE,
    year_val INT,
    month_val INT,
    day_val  INT,
    weekday  INT,
    is_weekend BOOLEAN
) LIFECYCLE 0;

-- 预填充 10 年日期:
INSERT OVERWRITE TABLE dim_date
SELECT DATE_ADD(DATE '2020-01-01', pos) AS d,
       YEAR(DATE_ADD(DATE '2020-01-01', pos)),
       MONTH(DATE_ADD(DATE '2020-01-01', pos)),
       DAY(DATE_ADD(DATE '2020-01-01', pos)),
       WEEKDAY(DATE_ADD(DATE '2020-01-01', pos)),
       WEEKDAY(DATE_ADD(DATE '2020-01-01', pos)) IN (0, 6)
FROM (SELECT 1) dummy
LATERAL VIEW POSEXPLODE(SPLIT(SPACE(3652), ' ')) t AS pos, val;

-- 使用辅助表填充:
SELECT dd.d, COALESCE(s.amount, 0) AS amount
FROM dim_date dd
LEFT JOIN daily_sales s ON dd.d = s.sale_date
WHERE dd.d BETWEEN DATE '2024-01-01' AND DATE '2024-01-31'
ORDER BY dd.d;

-- ============================================================
-- 6. 横向对比与引擎开发者启示
-- ============================================================

-- generate_series 等价方案:
--   MaxCompute: posexplode + split(space(n))（Hive workaround）
--   Hive:       相同方案
--   BigQuery:   GENERATE_DATE_ARRAY / GENERATE_ARRAY
--   PostgreSQL: generate_series（最优雅）
--   Snowflake:  GENERATOR + ROW_NUMBER

-- 对引擎开发者:
-- 1. generate_series 类的序列生成函数是高频需求 — 应内置
-- 2. IGNORE NULLS 窗口选项简化了 Forward Fill — 值得支持
-- 3. 日期维度表是数据仓库的标准实践 — 引擎应优化小表 JOIN
-- 4. posexplode + split(space(n)) 是聪明但不直观的 hack — 证明了内置方案的必要
