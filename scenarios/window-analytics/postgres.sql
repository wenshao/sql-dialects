-- PostgreSQL: 窗口函数实战分析
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html
--   [2] PostgreSQL Documentation - Window Function Processing
--       https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   daily_sales(sale_date DATE, product_id INT, region VARCHAR,
--               amount NUMERIC(10,2), quantity INT)
--   user_events(user_id INT, event_time TIMESTAMP, event_type VARCHAR,
--               page VARCHAR)
--   employee_salaries(emp_id INT, department VARCHAR, salary NUMERIC(10,2),
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
FROM daily_sales;

-- 7 天移动平均（按产品分组）
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- 30 天移动平均（RANGE 帧，按实际日期范围）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;
-- PostgreSQL 支持 RANGE + INTERVAL，适合有日期间隔的数据

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

-- 环比（Month-over-Month）
WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date)::DATE AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_TRUNC('month', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(
           (total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100,
       2) AS mom_pct
FROM monthly;

-- 同比（Year-over-Year）
WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date)::DATE AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_TRUNC('month', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year_same_month,
       ROUND(
           (total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100,
       2) AS yoy_pct
FROM monthly;

-- 按区域的同比环比
WITH monthly_region AS (
    SELECT region,
           DATE_TRUNC('month', sale_date)::DATE AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY region, DATE_TRUNC('month', sale_date)
)
SELECT region, sale_month, total_amount,
       ROUND((total_amount - LAG(total_amount) OVER w)
           / NULLIF(LAG(total_amount) OVER w, 0) * 100, 2) AS mom_pct,
       ROUND((total_amount - LAG(total_amount, 12) OVER w)
           / NULLIF(LAG(total_amount, 12) OVER w, 0) * 100, 2) AS yoy_pct
FROM monthly_region
WINDOW w AS (PARTITION BY region ORDER BY sale_month);
-- PostgreSQL 支持 WINDOW 子句定义命名窗口

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- 区域内占比
SELECT region, product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region
FROM daily_sales
GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- 聚合函数方式
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90
FROM employee_salaries
GROUP BY department;

-- 窗口函数方式（每行都带中位数）
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
               WHEN event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) > INTERVAL '30 minutes'
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
       MAX(event_time) - MIN(event_time) AS session_duration,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path  -- PostgreSQL 特有
FROM sessions
GROUP BY user_id, session_num
ORDER BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================

SELECT emp_id, department, salary, hire_date,
       FIRST_VALUE(salary) OVER w AS first_hire_salary,
       LAST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_hire_salary,
       FIRST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY salary DESC
       ) AS highest_salary
FROM employee_salaries
WINDOW w AS (PARTITION BY department ORDER BY hire_date);

-- NTH_VALUE（PostgreSQL 支持）
SELECT emp_id, department, salary,
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
       amount - LAG(amount) OVER w AS daily_change,
       ROUND((amount - LAG(amount) OVER w)
           / NULLIF(LAG(amount) OVER w, 0) * 100, 2) AS daily_change_pct,
       CASE
           WHEN amount > LAG(amount) OVER w
            AND LAG(amount) OVER w > LAG(amount, 2) OVER w
           THEN 'uptrend'
           WHEN amount < LAG(amount) OVER w
            AND LAG(amount) OVER w < LAG(amount, 2) OVER w
           THEN 'downtrend'
           ELSE 'neutral'
       END AS trend
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);

-- ============================================================
-- 8. 累计分布（PERCENT_RANK, CUME_DIST, NTILE）
-- ============================================================

SELECT emp_id, department, salary,
       RANK() OVER w AS salary_rank,
       DENSE_RANK() OVER w AS salary_dense_rank,
       PERCENT_RANK() OVER w AS pct_rank,
       ROUND(CUME_DIST() OVER w::NUMERIC, 4) AS cum_dist,
       NTILE(4) OVER w AS quartile,
       NTILE(10) OVER w AS decile,
       NTILE(100) OVER w AS percentile
FROM employee_salaries
WINDOW w AS (ORDER BY salary);

-- 部门内分布
SELECT emp_id, department, salary,
       PERCENT_RANK() OVER dept_w AS dept_pct_rank,
       NTILE(4) OVER dept_w AS dept_quartile,
       CASE NTILE(4) OVER dept_w
           WHEN 1 THEN 'Q1 (lowest 25%)'
           WHEN 2 THEN 'Q2'
           WHEN 3 THEN 'Q3'
           WHEN 4 THEN 'Q4 (highest 25%)'
       END AS quartile_label
FROM employee_salaries
WINDOW dept_w AS (PARTITION BY department ORDER BY salary);

-- ============================================================
-- 9. 性能提示
-- ============================================================

-- 对窗口函数的 ORDER BY 列创建索引
CREATE INDEX idx_sales_date ON daily_sales (sale_date);
CREATE INDEX idx_sales_product_date ON daily_sales (product_id, sale_date);
CREATE INDEX idx_events_user_time ON user_events (user_id, event_time);

-- PostgreSQL 支持所有 SQL 标准窗口函数
-- 支持 ROWS, RANGE, GROUPS（PostgreSQL 11+）帧
-- 支持 WINDOW 子句定义命名窗口
-- 支持 FILTER 子句（PostgreSQL 9.4+）
-- 支持 EXCLUDE 子句（PostgreSQL 11+）
