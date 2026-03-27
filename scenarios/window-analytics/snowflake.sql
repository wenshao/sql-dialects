-- Snowflake: 窗口函数实战分析
--
-- 参考资料:
--   [1] Snowflake Documentation - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic
--   [2] Snowflake Documentation - Window Frames
--       https://docs.snowflake.com/en/sql-reference/functions-analytic#window-frames

-- ============================================================
-- 假设表结构:
--   daily_sales(sale_date DATE, product_id NUMBER, region VARCHAR,
--               amount NUMBER(10,2), quantity NUMBER)
--   user_events(user_id NUMBER, event_time TIMESTAMP_NTZ, event_type VARCHAR,
--               page VARCHAR)
--   employee_salaries(emp_id NUMBER, department VARCHAR, salary NUMBER(10,2),
--                     hire_date DATE)

-- ============================================================
-- 1. 移动平均（Moving Average）
-- ============================================================

SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

-- 按产品的移动平均
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_month
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(DIV0(
           total_amount - LAG(total_amount) OVER (ORDER BY sale_month),
           LAG(total_amount) OVER (ORDER BY sale_month)
       ) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(DIV0(
           total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month),
           LAG(total_amount, 12) OVER (ORDER BY sale_month)
       ) * 100, 2) AS yoy_pct
FROM monthly;
-- Snowflake 的 DIV0 函数：除零返回 0（DIV0NULL 返回 NULL）

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;
-- Snowflake 支持 RATIO_TO_REPORT，比手动除更简洁

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
       MEDIAN(salary) AS median_builtin          -- Snowflake 内置 MEDIAN 函数
FROM employee_salaries
GROUP BY department;

-- 近似百分位（大数据集）
SELECT department,
       APPROX_PERCENTILE(salary, 0.5) AS approx_median,
       APPROX_PERCENTILE(salary, 0.99) AS approx_p99
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type, page,
           CASE
               WHEN DATEDIFF('minute',
                   LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
                   event_time) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
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
       DATEDIFF('second', MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type) WITHIN GROUP (ORDER BY event_time) AS event_path,
       ARRAY_AGG(DISTINCT page) AS pages_visited
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

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change,
       ROUND(DIV0NULL(
           amount - LAG(amount) OVER (ORDER BY sale_date),
           LAG(amount) OVER (ORDER BY sale_date)
       ) * 100, 2) AS change_pct
FROM daily_sales;

-- CONDITIONAL_TRUE_EVENT（Snowflake 特有：条件事件计数）
SELECT sale_date, amount,
       CONDITIONAL_TRUE_EVENT(amount > LAG(amount) OVER (ORDER BY sale_date))
           OVER (ORDER BY sale_date) AS consecutive_growth_count
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
       NTILE(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;

-- Snowflake 特有: WIDTH_BUCKET（等宽分桶）
SELECT emp_id, salary,
       WIDTH_BUCKET(salary, 30000, 200000, 10) AS salary_bucket
FROM employee_salaries;
