# TDSQL: 窗口函数实战分析

> 参考资料:
> - [TDSQL for MySQL Documentation](https://cloud.tencent.com/document/product/557)
> - MySQL 8.0 Window Functions (TDSQL 兼容)


## TDSQL 兼容 MySQL 协议，窗口函数语法同 MySQL 8.0

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

## 同比/环比


```sql
WITH monthly AS (
    SELECT DATE_FORMAT(sale_date, '%Y-%m-01') AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY DATE_FORMAT(sale_date, '%Y-%m-01')
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

## 占比


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;
```

## 百分位数 / 中位数（使用 NTILE 模拟）


```sql
WITH ranked AS (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary) AS rn,
           COUNT(*) OVER (PARTITION BY department) AS cnt
    FROM employee_salaries
)
SELECT department, AVG(salary) AS median_salary
FROM ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2))
GROUP BY department;
```

## 会话化


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN TIMESTAMPDIFF(MINUTE, LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time), event_time) > 30
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
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);
```

## 累计分布


```sql
SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;
```

TDSQL 兼容 MySQL 8.0 窗口函数
分布式版本中窗口函数在各分片上执行后合并
建议 PARTITION BY 列与 shardkey 对齐以减少跨分片查询
