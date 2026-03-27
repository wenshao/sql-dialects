-- Cloud Spanner: 窗口函数实战分析
--
-- 参考资料:
--   [1] Cloud Spanner Documentation - Analytic Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/analytic-function-concepts
--   [2] Cloud Spanner Documentation - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators

-- 假设表结构 (GoogleSQL):
--   daily_sales(sale_date DATE, product_id INT64, region STRING,
--               amount NUMERIC, quantity INT64)
--   user_events(user_id INT64, event_time TIMESTAMP, event_type STRING, page STRING)
--   employee_salaries(emp_id INT64, department STRING, salary NUMERIC, hire_date DATE)

-- ============================================================
-- 1. 移动平均
-- ============================================================

SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ) AS ma_3d,
       AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS ma_7d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC(sale_date, MONTH) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_month
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       SAFE_DIVIDE(total_amount - LAG(total_amount) OVER (ORDER BY sale_month),
           LAG(total_amount) OVER (ORDER BY sale_month)) * 100 AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       SAFE_DIVIDE(total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month),
           LAG(total_amount, 12) OVER (ORDER BY sale_month)) * 100 AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       SUM(amount) / SUM(SUM(amount)) OVER () * 100 AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

SELECT DISTINCT department,
       PERCENTILE_CONT(salary, 0.5) OVER (PARTITION BY department) AS median_salary,
       PERCENTILE_CONT(salary, 0.25) OVER (PARTITION BY department) AS p25,
       PERCENTILE_CONT(salary, 0.75) OVER (PARTITION BY department) AS p75
FROM employee_salaries;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN TIMESTAMP_DIFF(event_time, LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time), MINUTE) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time
    ) AS session_num
    FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       TIMESTAMP_DIFF(MAX(event_time), MIN(event_time), SECOND) AS duration_sec,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path
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
       ) AS last_hire_salary
FROM employee_salaries;

-- ============================================================
-- 7. LEAD / LAG
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;

-- ============================================================
-- 8. 累计分布
-- ============================================================

SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

-- Spanner 使用 GoogleSQL 方言
-- PERCENTILE_CONT 语法同 BigQuery（非 SQL 标准的 WITHIN GROUP）
-- 支持 SAFE_DIVIDE 避免除零错误
-- 分布式全局一致性事务保证窗口函数结果正确
