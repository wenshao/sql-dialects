-- ClickHouse: 窗口函数实战分析
--
-- 参考资料:
--   [1] ClickHouse Documentation - Window Functions (ClickHouse 21.1+)
--       https://clickhouse.com/docs/en/sql-reference/window-functions
--   [2] ClickHouse Documentation - Aggregate Functions
--       https://clickhouse.com/docs/en/sql-reference/aggregate-functions

-- ============================================================
-- 注意：窗口函数需要 ClickHouse 21.1+，完整支持 22.8+
-- ============================================================

-- 假设表结构:
--   daily_sales(sale_date Date, product_id UInt32, region String,
--               amount Decimal(10,2), quantity UInt32)
--   user_events(user_id UInt64, event_time DateTime, event_type String, page String)
--   employee_salaries(emp_id UInt32, department String, salary Decimal(10,2),
--                     hire_date Date)

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

-- 30 天移动平均（RANGE 帧用数值类型）
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY toUInt32(sale_date)
           RANGE BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

-- ClickHouse 特有：数组函数实现移动平均（高性能）
SELECT sale_date, amount,
       arrayAvg(arraySlice(
           groupArray(amount) OVER (ORDER BY sale_date),
           greatest(1, row_number() OVER (ORDER BY sale_date) - 6),
           least(7, row_number() OVER (ORDER BY sale_date))
       )) AS ma_7d_array
FROM daily_sales;

-- ============================================================
-- 2. 同比/环比（YoY / MoM）
-- ============================================================

WITH monthly AS (
    SELECT toStartOfMonth(sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_month
)
SELECT sale_month, total_amount,
       lagInFrame(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       round(
           (total_amount - lagInFrame(total_amount) OVER (ORDER BY sale_month))
           / nullIf(lagInFrame(total_amount) OVER (ORDER BY sale_month), 0) * 100,
       2) AS mom_pct,
       lagInFrame(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       round(
           (total_amount - lagInFrame(total_amount, 12) OVER (ORDER BY sale_month))
           / nullIf(lagInFrame(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100,
       2) AS yoy_pct
FROM monthly;
-- ClickHouse 使用 lagInFrame / leadInFrame（带 InFrame 后缀）

-- ============================================================
-- 3. 占比（Percentage of Total）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       round(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

-- 区域内占比
SELECT region, product_id,
       SUM(amount) AS product_total,
       round(SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region
FROM daily_sales
GROUP BY region, product_id;

-- ============================================================
-- 4. 百分位数 / 中位数
-- ============================================================

-- ClickHouse 聚合函数方式
SELECT department,
       median(salary) AS median_salary,
       quantile(0.25)(salary) AS p25,
       quantile(0.75)(salary) AS p75,
       quantile(0.90)(salary) AS p90,
       quantile(0.99)(salary) AS p99
FROM employee_salaries
GROUP BY department;

-- 多个百分位一次计算
SELECT department,
       quantiles(0.25, 0.5, 0.75, 0.9, 0.99)(salary) AS percentiles
FROM employee_salaries
GROUP BY department;

-- 精确百分位
SELECT department,
       quantileExact(0.5)(salary) AS exact_median
FROM employee_salaries
GROUP BY department;

-- ============================================================
-- 5. 会话化（Sessionization）
-- ============================================================

WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN dateDiff('minute',
                   lagInFrame(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
                   event_time) > 30
               OR lagInFrame(event_time) OVER (PARTITION BY user_id ORDER BY event_time) = toDateTime(0)
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
       min(event_time) AS session_start,
       max(event_time) AS session_end,
       dateDiff('second', min(event_time), max(event_time)) AS duration_sec,
       count() AS event_count,
       groupArray(event_type) AS event_path     -- ClickHouse 数组聚合
FROM sessions
GROUP BY user_id, session_num;

-- ============================================================
-- 6. FIRST_VALUE / LAST_VALUE
-- ============================================================

SELECT emp_id, department, salary, hire_date,
       first_value(salary) OVER (
           PARTITION BY department ORDER BY hire_date
       ) AS first_hire_salary,
       last_value(salary) OVER (
           PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_hire_salary
FROM employee_salaries;

-- nth_value（ClickHouse 22.8+）
SELECT emp_id, department, salary,
       nth_value(salary, 2) OVER (
           PARTITION BY department ORDER BY salary DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS second_highest
FROM employee_salaries;

-- ============================================================
-- 7. LEAD / LAG 趋势检测
-- ============================================================

SELECT sale_date, amount,
       lagInFrame(amount) OVER (ORDER BY sale_date) AS prev_day,
       leadInFrame(amount) OVER (ORDER BY sale_date) AS next_day,
       amount - lagInFrame(amount) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;

-- ============================================================
-- 8. 累计分布（PERCENT_RANK, CUME_DIST, NTILE）
-- ============================================================

SELECT emp_id, department, salary,
       rank() OVER (ORDER BY salary) AS salary_rank,
       dense_rank() OVER (ORDER BY salary) AS dense_rank,
       percent_rank() OVER (ORDER BY salary) AS pct_rank,
       cume_dist() OVER (ORDER BY salary) AS cum_dist,
       ntile(4) OVER (ORDER BY salary) AS quartile,
       ntile(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;

-- ClickHouse 窗口函数注意事项：
-- 使用 lagInFrame/leadInFrame 而非 LAG/LEAD（早期版本）
-- 22.8+ 版本开始支持标准 LAG/LEAD
-- 大数据量时考虑使用 ORDER BY + LIMIT 替代窗口函数
-- quantile* 系列函数非常丰富（近似、精确、加权等）
