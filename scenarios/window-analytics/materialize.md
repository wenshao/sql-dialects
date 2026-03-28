# Materialize: 窗口函数实战分析

> 参考资料:
> - [Materialize Documentation - Window Functions](https://materialize.com/docs/sql/functions/#window-functions)
> - [Materialize Documentation - SQL Reference](https://materialize.com/docs/sql/)


## Materialize 兼容 PostgreSQL，支持增量维护的窗口函数

假设表结构同 PostgreSQL

## 移动平均


```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       )::NUMERIC, 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       )::NUMERIC, 2) AS ma_7d
FROM daily_sales;
```

## 同比/环比


```sql
WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date)::DATE AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_TRUNC('month', sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount) OVER (ORDER BY sale_month) AS prev_month,
       ROUND((total_amount - LAG(total_amount) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct
FROM monthly;
```

## 占比


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;
```

## 百分位数 / 中位数（Materialize 支持有限）


## 使用 NTILE 模拟四分位

```sql
SELECT emp_id, department, salary,
       NTILE(4) OVER (PARTITION BY department ORDER BY salary) AS quartile
FROM employee_salaries;
```

## 会话化


```sql
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
       COUNT(*) AS event_count
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
       ) AS last_hire_salary
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
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       NTILE(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;
```

Materialize 特色：窗口函数结果自动增量维护
当源数据变化时，物化视图中的窗口函数结果自动更新
CREATE MATERIALIZED VIEW sales_with_ma AS
SELECT sale_date, amount,
AVG(amount) OVER (ORDER BY sale_date ROWS 6 PRECEDING) AS ma_7d
FROM daily_sales;
