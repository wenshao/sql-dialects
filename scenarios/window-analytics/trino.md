# Trino: 窗口分析实战

> 参考资料:
> - [Trino Documentation - Window Functions](https://trino.io/docs/current/functions/window.html)
> - [Trino Documentation - Aggregate Functions](https://trino.io/docs/current/functions/aggregate.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 移动平均


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

30 天移动平均（Trino 支持 RANGE + INTERVAL）
```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29' DAY PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

```

## 同比/环比


```sql
WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_TRUNC('month', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(
           CAST(total_amount - LAG(total_amount) OVER (ORDER BY sale_month) AS DOUBLE)
           / NULLIF(CAST(LAG(total_amount) OVER (ORDER BY sale_month) AS DOUBLE), 0) * 100,
       2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(
           CAST(total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month) AS DOUBLE)
           / NULLIF(CAST(LAG(total_amount, 12) OVER (ORDER BY sale_month) AS DOUBLE), 0) * 100,
       2) AS yoy_pct
FROM monthly;

```

## 占比


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(CAST(SUM(amount) AS DOUBLE)
           / CAST(SUM(SUM(amount)) OVER () AS DOUBLE) * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

```

## 百分位数 / 中位数


```sql
SELECT department,
       APPROX_PERCENTILE(salary, 0.5) AS approx_median,
       APPROX_PERCENTILE(salary, 0.25) AS approx_p25,
       APPROX_PERCENTILE(salary, 0.75) AS approx_p75,
       APPROX_PERCENTILE(salary, 0.90) AS approx_p90,
       APPROX_PERCENTILE(salary, ARRAY[0.25, 0.5, 0.75, 0.9]) AS percentiles
FROM employee_salaries
GROUP BY department;

```

## 会话化


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN DATE_DIFF('minute',
                   LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time),
                   event_time) > 30
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
       DATE_DIFF('second', MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       ARRAY_AGG(event_type ORDER BY event_time) AS event_path
FROM sessions
GROUP BY user_id, session_num;

```

## FIRST_VALUE / LAST_VALUE


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

## LEAD / LAG


```sql
SELECT sale_date, amount,
       LAG(amount) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;

```

## 累计分布


```sql
SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       NTILE(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;

```

Trino 窗口函数完整支持 SQL 标准
支持 RANGE + INTERVAL 帧
支持 GROUPS 帧类型
APPROX_PERCENTILE 适合大数据集分布式计算
