-- SQL Server: 窗口函数实战分析
--
-- 参考资料:
--   [1] SQL Server - Window Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql

-- ============================================================
-- 1. 移动平均（Moving Average）
-- ============================================================
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d,
       ROUND(AVG(amount) OVER (ORDER BY sale_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 2) AS ma_30d
FROM daily_sales;

-- SQL Server 不支持 RANGE + INTERVAL 帧（只能用 ROWS 物理偏移）
-- PostgreSQL: RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW（日期范围窗口）

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================
;WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(sale_date), MONTH(sale_date), 1) AS sale_month,
           SUM(amount) AS total FROM daily_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
)
SELECT sale_month, total,
       LAG(total) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total - LAG(total) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct,
       LAG(total, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND((total - LAG(total, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total, 12) OVER (ORDER BY sale_month), 0) * 100, 2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================
SELECT product_id, SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales GROUP BY product_id ORDER BY pct_of_total DESC;

-- 区域内占比
SELECT region, product_id, SUM(amount) AS total,
       ROUND(SUM(amount) * 100.0 / SUM(SUM(amount)) OVER (PARTITION BY region), 2) AS pct_in_region
FROM daily_sales GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================
SELECT DISTINCT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
           OVER (PARTITION BY department) AS median,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary)
           OVER (PARTITION BY department) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary)
           OVER (PARTITION BY department) AS p75
FROM employee_salaries;

-- SQL Server 的 PERCENTILE_CONT 只能用作窗口函数（不能用作聚合函数）
-- 这导致必须加 DISTINCT（否则每行都返回重复结果）

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================
;WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE WHEN DATEDIFF(MINUTE,
               LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
               event_time) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0 END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time ROWS UNBOUNDED PRECEDING
    ) AS session_num FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start, MAX(event_time) AS session_end,
       DATEDIFF(SECOND, MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       STRING_AGG(event_type, ' -> ') WITHIN GROUP (ORDER BY event_time) AS event_path
FROM sessions GROUP BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================
SELECT emp_id, department, salary,
       FIRST_VALUE(salary) OVER (PARTITION BY department ORDER BY hire_date) AS first_salary,
       LAST_VALUE(salary) OVER (PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_salary
FROM employee_salaries;

-- LAST_VALUE 必须显式指定帧（默认帧只到 CURRENT ROW）

-- SQL Server 不支持 NTH_VALUE——用 ROW_NUMBER + CTE 模拟
;WITH ranked AS (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn
    FROM employee_salaries
)
SELECT department, salary AS second_highest FROM ranked WHERE rn = 2;

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================
SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change,
       ROUND((amount - LAG(amount) OVER (ORDER BY sale_date))
           / NULLIF(LAG(amount) OVER (ORDER BY sale_date), 0) * 100, 2) AS change_pct
FROM daily_sales;

-- ============================================================
-- 8. 累计分布
-- ============================================================
SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       ROUND(PERCENT_RANK() OVER (ORDER BY salary), 4) AS pct_rank,
       ROUND(CUME_DIST() OVER (ORDER BY salary), 4) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

-- 版本说明:
-- 2005+ : ROW_NUMBER, RANK, DENSE_RANK, NTILE, 聚合窗口函数
-- 2012+ : LAG, LEAD, FIRST_VALUE, LAST_VALUE, ROWS/RANGE 帧
-- 2012+ : PERCENTILE_CONT, PERCENTILE_DISC, PERCENT_RANK, CUME_DIST
-- 2017+ : STRING_AGG（会话化中使用）
-- 2022+ : WINDOW 子句（命名窗口，预览）
-- 不支持: NTH_VALUE, RANGE + INTERVAL, WINDOW 子句（2022 之前）
