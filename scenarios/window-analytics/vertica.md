# Vertica: 窗口函数实战分析

> 参考资料:
> - [Vertica Documentation - Analytic Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/AnalyticFunctions.htm)
> - [Vertica Documentation - Window Framing](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Analytic/WindowFraming.htm)


假设表结构:
daily_sales(sale_date DATE, product_id INT, region VARCHAR(50),
amount NUMERIC(10,2), quantity INT)
user_events(user_id INT, event_time TIMESTAMP, event_type VARCHAR(50), page VARCHAR(255))
employee_salaries(emp_id INT, department VARCHAR(50), salary NUMERIC(10,2), hire_date DATE)

## 1. 移动平均


```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d
FROM daily_sales;
```


30 天移动平均（Vertica 支持 RANGE + INTERVAL）
```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;
```


Vertica 特有: 时间序列填充
```sql
SELECT ts, amount,
       AVG(amount) OVER (ORDER BY ts ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma_7d
FROM daily_sales
TIMESERIES ts AS '1 day' OVER (ORDER BY sale_date);
```


## 2. 同比/环比


```sql
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
```


## 3. 占比


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;
```


## 4. 百分位数 / 中位数


```sql
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       MEDIAN(salary) AS median_builtin,
       APPROXIMATE_PERCENTILE(salary USING PARAMETERS percentile=0.5) AS approx_median
FROM employee_salaries
GROUP BY department;
```


## 5. 会话化


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CONDITIONAL_TRUE_EVENT(
               DATEDIFF('minute', LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ), event_time) > 30
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
           ) OVER (PARTITION BY user_id ORDER BY event_time) AS session_num
    FROM user_events
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       DATEDIFF('second', MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count
FROM event_gaps
GROUP BY user_id, session_num;
-- Vertica 特有: CONDITIONAL_TRUE_EVENT 简化会话化
```


## 6. FIRST_VALUE / LAST_VALUE


```sql
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
```


## 7. LEAD / LAG


```sql
SELECT sale_date, amount,
       LAG(amount) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;
```


Vertica 特有: CONDITIONAL_CHANGE_EVENT（变化事件计数）
```sql
SELECT sale_date, region,
       CONDITIONAL_CHANGE_EVENT(region) OVER (ORDER BY sale_date) AS region_change_count
FROM daily_sales;
```


## 8. 累计分布


```sql
SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;
```


Vertica 特有分析函数:
CONDITIONAL_TRUE_EVENT: 条件事件计数
CONDITIONAL_CHANGE_EVENT: 变化事件计数
TIMESERIES: 时间序列填充
EXPONENTIAL_MOVING_AVERAGE: 指数移动平均
支持 RANGE + INTERVAL 帧
