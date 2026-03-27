-- BigQuery: 窗口函数实战分析
--
-- 参考资料:
--   [1] BigQuery Documentation - Analytic Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/analytic-function-concepts
--   [2] BigQuery Documentation - Navigation Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/navigation_functions

-- ============================================================
-- 假设表结构 (project.dataset.*):
--   daily_sales(sale_date DATE, product_id INT64, region STRING,
--               amount NUMERIC, quantity INT64)
--   user_events(user_id INT64, event_time TIMESTAMP, event_type STRING,
--               page STRING)
--   employee_salaries(emp_id INT64, department STRING, salary NUMERIC,
--                     hire_date DATE)

-- ============================================================
-- 1. 移动平均（Moving Average）
-- ============================================================

-- 3 天移动平均
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d
FROM `project.dataset.daily_sales`;

-- 7 天移动平均（按产品）
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM `project.dataset.daily_sales`;

-- 30 天移动平均（RANGE 帧需要数值类型 ORDER BY）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY UNIX_DATE(sale_date)
           RANGE BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM `project.dataset.daily_sales`;

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC(sale_date, MONTH) AS sale_month,
           SUM(amount) AS total_amount
    FROM `project.dataset.daily_sales`
    GROUP BY sale_month
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(SAFE_DIVIDE(
           total_amount - LAG(total_amount) OVER (ORDER BY sale_month),
           LAG(total_amount) OVER (ORDER BY sale_month)
       ) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(SAFE_DIVIDE(
           total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month),
           LAG(total_amount, 12) OVER (ORDER BY sale_month)
       ) * 100, 2) AS yoy_pct
FROM monthly;
-- BigQuery 的 SAFE_DIVIDE 自动处理除零，返回 NULL

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM `project.dataset.daily_sales`
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- 区域内占比（多维分析）
SELECT region, product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2)
           AS pct_of_grand_total
FROM `project.dataset.daily_sales`
GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- BigQuery 支持 PERCENTILE_CONT 和 PERCENTILE_DISC（仅作为分析函数）
SELECT DISTINCT department,
       PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY department) AS median_salary,
       PERCENTILE_CONT(salary, 0.25) OVER (PARTITION BY department) AS p25,
       PERCENTILE_CONT(salary, 0.75) OVER (PARTITION BY department) AS p75,
       PERCENTILE_CONT(salary, 0.90) OVER (PARTITION BY department) AS p90
FROM `project.dataset.employee_salaries`;
-- 注意：BigQuery 中 PERCENTILE_CONT 的语法与 SQL 标准不同
-- BigQuery: PERCENTILE_CONT(expr, percentile) OVER (...)
-- SQL 标准: PERCENTILE_CONT(percentile) WITHIN GROUP (ORDER BY expr)

-- 近似百分位（大数据集推荐）
SELECT department,
       APPROX_QUANTILES(salary, 100)[OFFSET(50)] AS approx_median,
       APPROX_QUANTILES(salary, 100)[OFFSET(90)] AS approx_p90,
       APPROX_QUANTILES(salary, 100)[OFFSET(99)] AS approx_p99
FROM `project.dataset.employee_salaries`
GROUP BY department;

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN TIMESTAMP_DIFF(event_time, LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ), MINUTE) > 30
               OR LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM `project.dataset.user_events`
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
       TIMESTAMP_DIFF(MAX(event_time), MIN(event_time), SECOND) AS duration_sec,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path,
       ARRAY_AGG(DISTINCT page) AS pages_visited
FROM sessions
GROUP BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================

SELECT emp_id, department, salary, hire_date,
       FIRST_VALUE(salary) OVER w AS first_hire_salary,
       LAST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_hire_salary,
       NTH_VALUE(salary, 2) OVER (
           PARTITION BY department ORDER BY salary DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS second_highest
FROM `project.dataset.employee_salaries`
WINDOW w AS (PARTITION BY department ORDER BY hire_date);

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change,
       ROUND(SAFE_DIVIDE(amount - LAG(amount) OVER w,
           LAG(amount) OVER w) * 100, 2) AS change_pct
FROM `project.dataset.daily_sales`
WINDOW w AS (ORDER BY sale_date);

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
FROM `project.dataset.employee_salaries`
WINDOW w AS (ORDER BY salary);

-- BigQuery 按扫描数据量计费
-- 窗口函数不增加额外扫描成本（相对于 SELECT *）
-- 使用分区表 + 日期过滤减少扫描量
