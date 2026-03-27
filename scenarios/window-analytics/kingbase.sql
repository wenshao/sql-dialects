-- KingbaseES（人大金仓）: 窗口函数实战分析
--
-- 参考资料:
--   [1] KingbaseES 文档 - 窗口函数
--       https://help.kingbase.com.cn/v8/index.html
--   [2] PostgreSQL Documentation (KingbaseES 兼容 PostgreSQL)

-- KingbaseES 兼容 PostgreSQL，窗口函数语法完全相同

-- ============================================================
-- 1. 移动平均
-- ============================================================

SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       )::NUMERIC, 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW
       )::NUMERIC, 2) AS ma_30d
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比
-- ============================================================

WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date)::DATE AS sale_month,
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
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 5. 会话化
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time) > INTERVAL '30 minutes'
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
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path
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
FROM employee_salaries
WINDOW w AS (PARTITION BY department ORDER BY hire_date);

-- ============================================================
-- 7. LEAD / LAG
-- ============================================================

SELECT sale_date, amount,
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);

-- ============================================================
-- 8. 累计分布
-- ============================================================

SELECT emp_id, salary,
       RANK() OVER w AS salary_rank,
       DENSE_RANK() OVER w AS dense_rank,
       PERCENT_RANK() OVER w AS pct_rank,
       CUME_DIST() OVER w AS cum_dist,
       NTILE(4) OVER w AS quartile
FROM employee_salaries
WINDOW w AS (ORDER BY salary);

-- KingbaseES 完全兼容 PostgreSQL 窗口函数
-- 支持 WINDOW 子句、RANGE + INTERVAL 帧
-- 支持 PERCENTILE_CONT / PERCENTILE_DISC
-- 支持 NTH_VALUE
