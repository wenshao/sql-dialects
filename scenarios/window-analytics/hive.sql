-- Hive: 窗口函数实战分析
--
-- 参考资料:
--   [1] Apache Hive - Windowing and Analytics Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics
--   [2] Apache Hive - Built-in Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

-- ============================================================
-- 注意：窗口函数需要 Hive 0.11+
-- ============================================================

-- 假设表结构:
--   daily_sales(sale_date STRING, product_id BIGINT, region STRING,
--               amount DECIMAL(10,2), quantity INT)
--   user_events(user_id BIGINT, event_time TIMESTAMP, event_type STRING,
--               page STRING)
--   employee_salaries(emp_id BIGINT, department STRING, salary DECIMAL(10,2),
--                     hire_date STRING)

-- ============================================================
-- 1. 移动平均
-- ============================================================

SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

-- 按产品分组
SELECT sale_date, product_id, amount,
       ROUND(AVG(amount) OVER (
           PARTITION BY product_id ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT SUBSTR(sale_date, 1, 7) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY SUBSTR(sale_date, 1, 7)
)
SELECT sale_month, total_amount,
       LAG(total_amount, 1) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(
           (total_amount - LAG(total_amount, 1) OVER (ORDER BY sale_month))
           / LAG(total_amount, 1) OVER (ORDER BY sale_month) * 100,
       2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(
           (total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / LAG(total_amount, 12) OVER (ORDER BY sale_month) * 100,
       2) AS yoy_pct
FROM monthly;

-- ============================================================
-- 3. 占比
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- Hive 支持 PERCENTILE（整数列）和 PERCENTILE_APPROX
SELECT department,
       PERCENTILE_APPROX(salary, 0.5) AS median_salary,
       PERCENTILE_APPROX(salary, 0.25) AS p25,
       PERCENTILE_APPROX(salary, 0.75) AS p75,
       PERCENTILE_APPROX(salary, 0.90) AS p90,
       PERCENTILE_APPROX(salary, ARRAY(0.25, 0.5, 0.75, 0.9)) AS percentiles
FROM employee_salaries
GROUP BY department;

-- 精确百分位（仅 BIGINT 列）
-- SELECT department, PERCENTILE(CAST(salary * 100 AS BIGINT), 0.5) / 100.0
-- FROM employee_salaries GROUP BY department;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN UNIX_TIMESTAMP(event_time) -
                    UNIX_TIMESTAMP(LAG(event_time) OVER (
                        PARTITION BY user_id ORDER BY event_time
                    )) > 1800                   -- 30 分钟 = 1800 秒
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT *, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS session_num
    FROM event_gaps
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       UNIX_TIMESTAMP(MAX(event_time)) - UNIX_TIMESTAMP(MIN(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       COLLECT_LIST(event_type) AS event_path   -- Hive 数组聚合
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

-- NTH_VALUE 在 Hive 中不可用，使用 ROW_NUMBER 替代
WITH ranked AS (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS rn
    FROM employee_salaries
)
SELECT department, salary AS second_highest
FROM ranked WHERE rn = 2;

-- ============================================================
-- 7. LEAD / LAG
-- ============================================================

SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;

-- ============================================================
-- 8. 累计分布
-- ============================================================

SELECT emp_id, department, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

-- Hive 窗口函数支持：
-- ROW_NUMBER, RANK, DENSE_RANK, NTILE (0.11+)
-- LAG, LEAD, FIRST_VALUE, LAST_VALUE (0.11+)
-- PERCENT_RANK, CUME_DIST (0.11+)
-- 不支持 NTH_VALUE
-- 不支持 RANGE + INTERVAL 帧
-- PERCENTILE_APPROX 用于近似百分位
