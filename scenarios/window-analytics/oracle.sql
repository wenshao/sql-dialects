-- Oracle: 窗口函数实战分析
--
-- 参考资料:
--   [1] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html
--   [2] Oracle Documentation - Window Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- 假设表结构:
--   daily_sales(sale_date DATE, product_id NUMBER, region VARCHAR2(50),
--               amount NUMBER(10,2), quantity NUMBER)
--   user_events(user_id NUMBER, event_time TIMESTAMP, event_type VARCHAR2(50),
--               page VARCHAR2(255))
--   employee_salaries(emp_id NUMBER, department VARCHAR2(50), salary NUMBER(10,2),
--                     hire_date DATE)

-- ============================================================
-- 1. 移动平均（Moving Average）
-- ============================================================

SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- 30 天移动平均（Oracle 支持 RANGE + INTERVAL）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29' DAY PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

WITH monthly AS (
    SELECT TRUNC(sale_date, 'MM') AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY TRUNC(sale_date, 'MM')
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(
           (total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100,
       2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(
           (total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100,
       2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

-- Oracle 特有: RATIO_TO_REPORT
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- 区域内占比
SELECT region, product_id,
       SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region
FROM daily_sales
GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90,
       MEDIAN(salary) AS median_builtin           -- Oracle 内置 MEDIAN
FROM employee_salaries
GROUP BY department;

-- 窗口函数形式（每行带百分位）
SELECT emp_id, department, salary,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
           OVER (PARTITION BY department) AS dept_median
FROM employee_salaries;

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN (event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               )) * 24 * 60 > 30                -- Oracle DATE 相减得到天数
               OR LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT e.*,
           SUM(is_new_session) OVER (
               PARTITION BY user_id ORDER BY event_time
           ) AS session_num
    FROM event_gaps e
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       ROUND((MAX(event_time) - MIN(event_time)) * 86400) AS duration_sec,
       COUNT(*) AS event_count,
       LISTAGG(event_type, ' -> ') WITHIN GROUP (ORDER BY event_time) AS event_path
FROM sessions
GROUP BY user_id, session_num;

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

-- Oracle 特有: FIRST/LAST 聚合
SELECT department,
       MIN(salary) KEEP (DENSE_RANK FIRST ORDER BY hire_date) AS first_hire_salary,
       MIN(salary) KEEP (DENSE_RANK LAST ORDER BY hire_date) AS last_hire_salary
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================

SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change,
       ROUND(
           (amount - LAG(amount) OVER (ORDER BY sale_date))
           / NULLIF(LAG(amount) OVER (ORDER BY sale_date), 0) * 100,
       2) AS change_pct
FROM daily_sales;

-- ============================================================
-- 8. 累计分布（PERCENT_RANK, CUME_DIST, NTILE）
-- ============================================================

SELECT emp_id, department, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       ROUND(PERCENT_RANK() OVER (ORDER BY salary), 4) AS pct_rank,
       ROUND(CUME_DIST() OVER (ORDER BY salary), 4) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       NTILE(10) OVER (ORDER BY salary) AS decile,
       WIDTH_BUCKET(salary, 30000, 200000, 10) AS salary_bucket
FROM employee_salaries;

-- Oracle 是最早支持分析函数的数据库之一（Oracle 8i, 1999）
-- 支持 WINDOW 子句、GROUPS 帧类型（21c+）
-- 支持 RATIO_TO_REPORT、MEDIAN、KEEP (DENSE_RANK)
-- 支持 RANGE + INTERVAL 帧
