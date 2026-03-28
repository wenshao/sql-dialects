# DB2: 窗口函数实战分析

> 参考资料:
> - [IBM Db2 Documentation - OLAP Specifications](https://www.ibm.com/docs/en/db2/11.5?topic=expressions-olap-specifications)
> - [IBM Db2 Documentation - Window Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-aggregate)


假设表结构:
daily_sales(sale_date DATE, product_id INTEGER, region VARCHAR(50),
amount DECIMAL(10,2), quantity INTEGER)
user_events(user_id INTEGER, event_time TIMESTAMP, event_type VARCHAR(50), page VARCHAR(255))
employee_salaries(emp_id INTEGER, department VARCHAR(50), salary DECIMAL(10,2), hire_date DATE)

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

## 30 天移动平均（DB2 支持 RANGE）

```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN 29 DAYS PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;
```

## 同比/环比


```sql
WITH monthly AS (
    SELECT DATE(YEAR(sale_date) || '-' || LPAD(MONTH(sale_date), 2, '0') || '-01') AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
)
SELECT sale_month, total_amount,
       LAG(total_amount, 1) OVER (ORDER BY sale_month) AS prev_month,
       ROUND(DECFLOAT(total_amount - LAG(total_amount, 1) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 1) OVER (ORDER BY sale_month), 0) * 100, 2) AS mom_pct,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       ROUND(DECFLOAT(total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / NULLIF(LAG(total_amount, 12) OVER (ORDER BY sale_month), 0) * 100, 2) AS yoy_pct
FROM monthly;
```

## 占比


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(DECFLOAT(SUM(amount)) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;
```

## 百分位数 / 中位数


```sql
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary) AS median_disc,
       MEDIAN(salary) AS median_builtin
FROM employee_salaries
GROUP BY department;
```

## 会话化


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN TIMESTAMPDIFF(2,
                   CHAR(event_time - LAG(event_time) OVER (
                       PARTITION BY user_id ORDER BY event_time
                   ))) > 1800
               OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT e.*, SUM(is_new_session) OVER (
        PARTITION BY user_id ORDER BY event_time
    ) AS session_num
    FROM event_gaps e
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       COUNT(*) AS event_count,
       LISTAGG(event_type, ' -> ') WITHIN GROUP (ORDER BY event_time) AS event_path
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
       LAG(amount, 1) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount, 1) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;
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

DB2 是最早支持窗口函数的数据库之一
支持 RANGE + 日期间隔帧
支持 MEDIAN 内置函数
支持 PERCENTILE_CONT / PERCENTILE_DISC
