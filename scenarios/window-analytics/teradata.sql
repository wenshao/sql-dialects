-- Teradata: 窗口函数实战分析
--
-- 参考资料:
--   [1] Teradata Documentation - Window Functions
--       https://docs.teradata.com/r/SQL-Functions-Expressions-and-Predicates/Window-Aggregate-Functions
--   [2] Teradata Documentation - Ordered Analytical Functions
--       https://docs.teradata.com/r/SQL-Functions-Expressions-and-Predicates/Ordered-Analytical-Functions

-- 假设表结构:
--   daily_sales(sale_date DATE, product_id INTEGER, region VARCHAR(50),
--               amount DECIMAL(10,2), quantity INTEGER)
--   user_events(user_id INTEGER, event_time TIMESTAMP, event_type VARCHAR(50), page VARCHAR(255))
--   employee_salaries(emp_id INTEGER, department VARCHAR(50), salary DECIMAL(10,2), hire_date DATE)

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

-- Teradata 特有: MAVG（移动平均函数）
SELECT sale_date, amount,
       MAVG(amount, 7, sale_date) AS ma_7d_mavg
FROM daily_sales;

-- MSUM（移动求和）
SELECT sale_date, amount,
       MSUM(amount, 7, sale_date) AS msum_7d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT sale_date - EXTRACT(DAY FROM sale_date) + 1 AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_date - EXTRACT(DAY FROM sale_date) + 1
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       (total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100 AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       (total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100 AS yoy_pct
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

SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       MEDIAN(salary) AS median_builtin
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN (event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               )) MINUTE(4) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT e.*, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time
        ROWS UNBOUNDED PRECEDING
    ) AS session_num
    FROM event_gaps e
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       COUNT(*) AS event_count
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

-- Teradata 特有: MDIFF（移动差分）
SELECT sale_date, amount,
       MDIFF(amount, 1, sale_date) AS daily_diff
FROM daily_sales;

-- ============================================================
-- 8. 累计分布
-- ============================================================

SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       QUANTILE(10, salary) AS decile            -- Teradata 特有: QUANTILE
FROM employee_salaries;

-- Teradata 特有函数: MAVG, MSUM, MDIFF, MLINREG, QUANTILE
-- 这些函数比标准窗口函数更早出现
-- Teradata 是窗口函数的先驱之一
