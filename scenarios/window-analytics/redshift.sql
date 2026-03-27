-- Redshift: 窗口函数实战分析
--
-- 参考资料:
--   [1] AWS Redshift Documentation - Window Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Window_functions.html
--   [2] AWS Redshift Documentation - SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html

-- ============================================================
-- 假设表结构:
--   daily_sales(sale_date DATE, product_id INT, region VARCHAR(50),
--               amount DECIMAL(10,2), quantity INT)
--   user_events(user_id INT, event_time TIMESTAMP, event_type VARCHAR(50),
--               page VARCHAR(255))
--   employee_salaries(emp_id INT, department VARCHAR(50), salary DECIMAL(10,2),
--                     hire_date DATE)

-- ============================================================
-- 1. 移动平均
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

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_TRUNC('month', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND((total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100, 2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;
-- Redshift 支持 RATIO_TO_REPORT

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90,
       MEDIAN(salary) AS median_builtin
FROM employee_salaries
GROUP BY department;

-- 近似百分位（大数据集推荐）
SELECT department,
       APPROXIMATE PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary) AS approx_median
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN DATEDIFF(minute,
                   LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
                   event_time) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time ROWS UNBOUNDED PRECEDING
    ) AS session_num
    FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       DATEDIFF(second, MIN(event_time), MAX(event_time)) AS duration_sec,
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
           ROWS UNBOUNDED PRECEDING
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

SELECT emp_id, department, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       ROUND(PERCENT_RANK() OVER (ORDER BY salary)::NUMERIC, 4) AS pct_rank,
       ROUND(CUME_DIST() OVER (ORDER BY salary)::NUMERIC, 4) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       NTILE(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;

-- Redshift 性能提示：
-- 窗口函数在分布式环境下可能触发数据重分布
-- 使用 DISTKEY / SORTKEY 优化
-- RATIO_TO_REPORT、MEDIAN 是 Redshift 内置函数
-- Redshift 不支持 RANGE + INTERVAL 帧
