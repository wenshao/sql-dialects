-- PostgreSQL: 窗口函数实战分析 (Window Analytics)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html

-- ============================================================
-- 1. 移动平均
-- ============================================================

-- 7 天移动平均（按产品分组）
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d
FROM daily_sales;

-- 30 天移动平均（RANGE + INTERVAL，PostgreSQL 优势）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW), 2) AS ma_30d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比 (YoY / MoM)
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date)::DATE AS month, SUM(amount) AS total
    FROM daily_sales GROUP BY 1
)
SELECT month, total,
       LAG(total) OVER (ORDER BY month) AS prev_month,
       ROUND((total - LAG(total) OVER (ORDER BY month))
             / NULLIF(LAG(total) OVER (ORDER BY month), 0) * 100, 2) AS mom_pct,
       LAG(total, 12) OVER (ORDER BY month) AS prev_year,
       ROUND((total - LAG(total, 12) OVER (ORDER BY month))
             / NULLIF(LAG(total, 12) OVER (ORDER BY month), 0) * 100, 2) AS yoy_pct
FROM monthly;

-- WINDOW 子句复用窗口定义
SELECT region, month, total,
       ROUND((total - LAG(total) OVER w) / NULLIF(LAG(total) OVER w, 0) * 100, 2) AS mom
FROM monthly_region
WINDOW w AS (PARTITION BY region ORDER BY month);

-- ============================================================
-- 3. 占比 (Percentage of Total)
-- ============================================================

SELECT product_id, SUM(amount) AS total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales GROUP BY product_id;

-- 区域内占比
SELECT region, product_id, SUM(amount) AS total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region
FROM daily_sales GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75
FROM employee_salaries GROUP BY department;

-- ============================================================
-- 5. 会话化 (Sessionization)
-- ============================================================

WITH gaps AS (
    SELECT user_id, event_time, event_type,
           CASE WHEN event_time - LAG(event_time) OVER (
               PARTITION BY user_id ORDER BY event_time) > INTERVAL '30 min'
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0 END AS new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_time) AS session_num
    FROM gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS start, MAX(event_time) AS end,
       MAX(event_time) - MIN(event_time) AS duration,
       COUNT(*) AS events,
       ARRAY_AGG(event_type ORDER BY event_time) AS path  -- PostgreSQL: 聚合为数组
FROM sessions GROUP BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE / NTH_VALUE
-- ============================================================

SELECT emp_id, department, salary,
       FIRST_VALUE(salary) OVER w AS first_salary,
       NTH_VALUE(salary, 2) OVER (PARTITION BY department ORDER BY salary DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS second_highest
FROM employee_salaries
WINDOW w AS (PARTITION BY department ORDER BY hire_date);

-- 注意 LAST_VALUE 默认帧是 UNBOUNDED PRECEDING TO CURRENT ROW!
-- 需要显式 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING

-- ============================================================
-- 7. 累计分布
-- ============================================================

SELECT emp_id, salary,
       RANK() OVER w, DENSE_RANK() OVER w,
       ROUND(PERCENT_RANK() OVER w::NUMERIC, 4) AS pct_rank,
       NTILE(4) OVER w AS quartile
FROM employee_salaries
WINDOW w AS (ORDER BY salary);

-- ============================================================
-- 8. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. PostgreSQL 窗口函数优势:
--   RANGE + INTERVAL（日期范围帧，MySQL不支持）
--   GROUPS 帧模式 (11+)
--   EXCLUDE 子句 (11+, EXCLUDE CURRENT ROW/TIES/GROUP)
--   FILTER 子句 (9.4+, 条件窗口聚合)
--   WINDOW 子句（命名窗口复用）
--
-- 2. 缺失功能:
--   IGNORE NULLS（LAG/LEAD/FIRST_VALUE 的 NULL 跳过选项）
--   Oracle/BigQuery 支持，PostgreSQL 不支持（需 workaround）
--
-- 对引擎开发者:
--   WINDOW 子句不仅是语法糖——优化器可以识别共享窗口定义，
--   合并为单次排序+多次扫描，减少 I/O。
--   RANGE + INTERVAL 是时序分析的核心需求，必须支持。
--   GROUPS 帧模式（11+）处理 peer rows 更精确，值得实现。
