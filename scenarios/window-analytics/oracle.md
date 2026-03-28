# Oracle: 窗口分析

> 参考资料:
> - [Oracle SQL Language Reference - Analytic Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html)

## 移动平均 (Moving Average)

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

30 天移动平均（RANGE + INTERVAL，Oracle 独有能力）
```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29' DAY PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;
```

## 同比/环比 (YoY / MoM)

```sql
WITH monthly AS (
    SELECT TRUNC(sale_date, 'MM') AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales GROUP BY TRUNC(sale_date, 'MM')
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

## 占比: RATIO_TO_REPORT（Oracle 独有函数）

```sql
SELECT product_id, SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales GROUP BY product_id ORDER BY pct_of_total DESC;
```

区域内占比
```sql
SELECT region, product_id, SUM(amount) AS product_total,
       ROUND(RATIO_TO_REPORT(SUM(amount)) OVER (PARTITION BY region) * 100, 2)
           AS pct_within_region
FROM daily_sales GROUP BY region, product_id;
```

RATIO_TO_REPORT 是 Oracle 独有的便捷函数
其他数据库需要: SUM(col) / SUM(SUM(col)) OVER ()

## 百分位数 / 中位数

```sql
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       MEDIAN(salary) AS median_builtin        -- Oracle 独有的 MEDIAN 函数
FROM employee_salaries GROUP BY department;
```

窗口函数形式
```sql
SELECT emp_id, department, salary,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary)
           OVER (PARTITION BY department) AS dept_median
FROM employee_salaries;
```

## 会话化 (Sessionization)

```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN (event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               )) * 24 * 60 > 30              -- Oracle DATE 相减得天数
               OR LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) IS NULL
               THEN 1 ELSE 0
           END AS is_new_session
    FROM user_events
),
sessions AS (
    SELECT e.*,
           SUM(is_new_session) OVER (
               PARTITION BY user_id ORDER BY event_time
           ) AS session_num
    FROM event_gaps e
)
SELECT user_id, session_num,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       ROUND((MAX(event_time) - MIN(event_time)) * 86400) AS duration_sec,
       COUNT(*) AS event_count,
       LISTAGG(event_type, ' -> ') WITHIN GROUP (ORDER BY event_time) AS path
FROM sessions GROUP BY user_id, session_num;
```

## FIRST_VALUE / LAST_VALUE / NTH_VALUE

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

Oracle 独有: KEEP (DENSE_RANK) 聚合
```sql
SELECT department,
       MIN(salary) KEEP (DENSE_RANK FIRST ORDER BY hire_date) AS first_hire_salary,
       MIN(salary) KEEP (DENSE_RANK LAST ORDER BY hire_date) AS last_hire_salary
FROM employee_salaries GROUP BY department;
```

## 累计分布 (PERCENT_RANK, CUME_DIST, NTILE)

```sql
SELECT emp_id, department, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       ROUND(PERCENT_RANK() OVER (ORDER BY salary), 4) AS pct_rank,
       ROUND(CUME_DIST() OVER (ORDER BY salary), 4) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       WIDTH_BUCKET(salary, 30000, 200000, 10) AS salary_bucket
FROM employee_salaries;
```

## LEAD / LAG 趋势检测

```sql
SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change,
       ROUND(
           (amount - LAG(amount) OVER (ORDER BY sale_date))
           / NULLIF(LAG(amount) OVER (ORDER BY sale_date), 0) * 100,
       2) AS change_pct
FROM daily_sales;
```

## 对引擎开发者的总结

1. Oracle 是窗口函数的发明者（8i, 1999），其实现最完整。
2. RATIO_TO_REPORT、MEDIAN、KEEP (DENSE_RANK) 是 Oracle 独有的实用函数。
3. RANGE + INTERVAL 帧使时间序列分析更自然（按日期范围而非行数）。
4. LISTAGG + 窗口函数可以在每行带上组内路径信息。
### 会话化是窗口函数的经典应用: 标记边界 → 累计分组标记 → 按组聚合。

6. WIDTH_BUCKET 是直方图分桶的内置函数，OLAP 分析中很常用。
