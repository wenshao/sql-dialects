# Impala: 窗口函数实战分析

> 参考资料:
> - [Impala Documentation - Analytic Functions](https://impala.apache.org/docs/build/html/topics/impala_analytic_functions.html)
> - [Impala Documentation - Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


假设表结构:
daily_sales(sale_date STRING, product_id BIGINT, region STRING,
amount DECIMAL(10,2), quantity INT)
user_events(user_id BIGINT, event_time TIMESTAMP, event_type STRING, page STRING)
employee_salaries(emp_id BIGINT, department STRING, salary DECIMAL(10,2), hire_date STRING)

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


## 2. 同比/环比


```sql
WITH monthly AS (
    SELECT SUBSTR(sale_date, 1, 7) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY SUBSTR(sale_date, 1, 7)
)
SELECT sale_month, total_amount,
       LAG(total_amount, 1) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total_amount - LAG(total_amount, 1) OVER (ORDER BY sale_month))
           / LAG(total_amount, 1) OVER (ORDER BY sale_month) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND((total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / LAG(total_amount, 12) OVER (ORDER BY sale_month) * 100, 2) AS yoy_pct
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


Impala 支持 APPX_MEDIAN 和 PERCENTILE（近似）
```sql
SELECT department,
       APPX_MEDIAN(salary) AS approx_median,
       NDV(salary) AS distinct_count
FROM employee_salaries
GROUP BY department;
```


使用 NTILE 模拟百分位
```sql
SELECT department,
       MAX(CASE WHEN quartile = 2 THEN salary END) AS approx_median
FROM (
    SELECT department, salary,
           NTILE(4) OVER (PARTITION BY department ORDER BY salary) AS quartile
    FROM employee_salaries
) t
GROUP BY department;
```


## 5. 会话化


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN UNIX_TIMESTAMP(event_time) -
                    UNIX_TIMESTAMP(LAG(event_time) OVER (
                        PARTITION BY user_id ORDER BY event_time)) > 1800
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
       GROUP_CONCAT(event_type, ' -> ') AS event_path
FROM sessions
GROUP BY user_id, session_num;
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
       ) AS last_hire_salary
FROM employee_salaries;
```


## 7. LEAD / LAG


```sql
SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS daily_change
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


Impala 支持大部分窗口函数
APPX_MEDIAN 是 Impala 特有的近似中位数函数
不支持 PERCENTILE_CONT / PERCENTILE_DISC
不支持 NTH_VALUE
字符串聚合使用 GROUP_CONCAT
