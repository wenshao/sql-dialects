-- MariaDB: 窗口函数实战分析
--
-- 参考资料:
--   [1] MariaDB Documentation - Window Functions (MariaDB 10.2+)
--       https://mariadb.com/kb/en/window-functions/
--   [2] MariaDB Documentation - Window Frames
--       https://mariadb.com/kb/en/window-functions-overview/

-- ============================================================
-- 注意：窗口函数需要 MariaDB 10.2+
-- ============================================================

-- 假设表结构:
--   daily_sales(sale_date DATE, product_id INT, region VARCHAR(50),
--               amount DECIMAL(10,2), quantity INT)
--   user_events(user_id INT, event_time DATETIME, event_type VARCHAR(50),
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
       ), 2) AS ma_7d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT DATE_FORMAT(sale_date, '%Y-%m-01') AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_FORMAT(sale_date, '%Y-%m-01')
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct
FROM monthly;

-- ============================================================
-- 3. 占比
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- MariaDB 10.3.3+ 支持 PERCENTILE_CONT / PERCENTILE_DISC（窗口函数形式）
SELECT DISTINCT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY department)
           AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY department)
           AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY department)
           AS p75
FROM employee_salaries;

-- MariaDB 内置 MEDIAN（10.3.3+）
SELECT department,
       MEDIAN(salary) OVER (PARTITION BY department) AS median_salary
FROM employee_salaries;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN TIMESTAMPDIFF(MINUTE, LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ), event_time) > 30
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
       TIMESTAMPDIFF(SECOND, MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       GROUP_CONCAT(event_type ORDER BY event_time SEPARATOR ' -> ') AS event_path
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
       ROUND(PERCENT_RANK() OVER (ORDER BY salary), 4) AS pct_rank,
       ROUND(CUME_DIST() OVER (ORDER BY salary), 4) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

-- MariaDB 窗口函数特点：
-- 10.2+ 支持基本窗口函数
-- 10.3.3+ 支持 PERCENTILE_CONT/DISC, MEDIAN
-- 支持 NTH_VALUE
-- 不支持 RANGE + INTERVAL 帧
