-- SQLite: 窗口函数实战分析
--
-- 参考资料:
--   [1] SQLite Documentation - Window Functions (SQLite 3.25.0+, 2018-09)
--       https://www.sqlite.org/windowfunctions.html

-- ============================================================
-- 注意：窗口函数需要 SQLite 3.25.0+（2018 年 9 月发布）
-- ============================================================

-- 假设表结构:
--   daily_sales(sale_date TEXT, product_id INTEGER, region TEXT,
--               amount REAL, quantity INTEGER)
--   user_events(user_id INTEGER, event_time TEXT, event_type TEXT, page TEXT)
--   employee_salaries(emp_id INTEGER, department TEXT, salary REAL, hire_date TEXT)

-- ============================================================
-- 1. 移动平均（Moving Average）
-- ============================================================

-- 3 天移动平均
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d
FROM daily_sales;

-- 7 天移动平均
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- 30 天移动平均
-- SQLite 不支持 RANGE + INTERVAL，使用 ROWS 近似
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

WITH monthly AS (
    SELECT STRFTIME('%Y-%m', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY STRFTIME('%Y-%m', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(
           CAST(total_amount - LAG(total_amount) OVER (ORDER BY sale_month) AS REAL)
           / LAG(total_amount) OVER (ORDER BY sale_month) * 100,
       2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(
           CAST(total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month) AS REAL)
           / LAG(total_amount, 12) OVER (ORDER BY sale_month) * 100,
       2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) * 100.0 / SUM(SUM(amount)) OVER (), 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- 区域内占比
SELECT region, product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) * 100.0 / SUM(SUM(amount)) OVER (PARTITION BY region), 2)
           AS pct_within_region
FROM daily_sales
GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- SQLite 没有 PERCENTILE_CONT / PERCENTILE_DISC
-- 使用 NTILE 模拟
WITH ranked AS (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary) AS rn,
           COUNT(*) OVER (PARTITION BY department) AS cnt
    FROM employee_salaries
)
SELECT department,
       AVG(salary) AS median_salary
FROM ranked
WHERE rn IN (cnt / 2, cnt / 2 + 1)
   OR (cnt % 2 = 1 AND rn = (cnt + 1) / 2)
GROUP BY department;

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN (JULIANDAY(event_time) - JULIANDAY(LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ))) * 24 * 60 > 30
               OR LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) IS NULL
               THEN 1
               ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *,
           SUM(is_new_session) OVER (
               PARTITION BY user_id ORDER BY event_time
           ) AS session_num
    FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       ROUND((JULIANDAY(MAX(event_time)) - JULIANDAY(MIN(event_time))) * 86400) AS duration_sec,
       COUNT(*) AS event_count
FROM sessions
GROUP BY user_id, session_num;
-- SQLite 使用 JULIANDAY 进行日期运算

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================

SELECT emp_id, department, salary, hire_date,
       FIRST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY hire_date
       ) AS first_hire_salary,
       LAST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_hire_salary,
       NTH_VALUE(salary, 2) OVER (
           PARTITION BY department ORDER BY salary DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS second_highest
FROM employee_salaries;

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);
-- SQLite 3.28.0+ 支持 WINDOW 子句

-- ============================================================
-- 8. 累计分布（PERCENT_RANK, CUME_DIST, NTILE）
-- ============================================================

SELECT emp_id, department, salary,
       RANK() OVER w AS salary_rank,
       DENSE_RANK() OVER w AS dense_rank,
       ROUND(PERCENT_RANK() OVER w, 4) AS pct_rank,
       ROUND(CUME_DIST() OVER w, 4) AS cum_dist,
       NTILE(4) OVER w AS quartile,
       NTILE(10) OVER w AS decile
FROM employee_salaries
WINDOW w AS (ORDER BY salary);

-- SQLite 窗口函数支持：
-- ROW_NUMBER, RANK, DENSE_RANK, NTILE
-- LAG, LEAD, FIRST_VALUE, LAST_VALUE, NTH_VALUE
-- SUM, AVG, COUNT, MIN, MAX (作为窗口聚合)
-- PERCENT_RANK, CUME_DIST (3.28.0+)
-- 不支持 RANGE + INTERVAL 帧
-- 不支持 PERCENTILE_CONT / PERCENTILE_DISC
