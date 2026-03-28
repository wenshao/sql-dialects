# MaxCompute (ODPS): 窗口函数实战分析

> 参考资料:
> - [1] MaxCompute Documentation - Window Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/window-functions


## 1. 移动平均（股价/指标分析）


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

## 2. 同比/环比（MoM / YoY）


```sql
WITH monthly AS (
    SELECT SUBSTR(sale_date, 1, 7) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales GROUP BY SUBSTR(sale_date, 1, 7)
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

## 3. 占比分析（产品/地区贡献度）


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales GROUP BY product_id;

```

## 4. 百分位数 / 中位数


```sql
SELECT department,
       PERCENTILE(CAST(salary AS BIGINT), 0.5) AS median_salary,
       PERCENTILE(CAST(salary AS BIGINT), 0.25) AS p25,
       PERCENTILE(CAST(salary AS BIGINT), 0.75) AS p75,
       PERCENTILE(CAST(salary AS BIGINT), 0.9) AS p90
FROM employee_salaries GROUP BY department;

```

## 5. 会话化分析（用户行为分析）


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN UNIX_TIMESTAMP(event_time, 'yyyy-MM-dd HH:mm:ss') -
                    UNIX_TIMESTAMP(LAG(event_time, 1) OVER (
                        PARTITION BY user_id ORDER BY event_time),
                        'yyyy-MM-dd HH:mm:ss') > 1800
               OR LAG(event_time, 1) OVER (
                   PARTITION BY user_id ORDER BY event_time) IS NULL
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
       WM_CONCAT(',', event_type) AS event_path
FROM sessions GROUP BY user_id, session_num;

```

 会话化原理:
   间隔 > 30 分钟 → 新会话（is_new_session = 1）
   累计 is_new_session → 会话编号
   GROUP BY 会话编号 → 会话级统计

## 6. FIRST_VALUE / LAST_VALUE / NTH_VALUE


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

## 7. LAG / LEAD 变化分析


```sql
SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS daily_change,
       ROUND((amount - LAG(amount, 1, 0) OVER (ORDER BY sale_date))
           / NULLIF(LAG(amount, 1, 0) OVER (ORDER BY sale_date), 0) * 100, 2)
           AS change_pct
FROM daily_sales;

```

## 8. 累计分布 / 分位排名


```sql
SELECT emp_id, salary,
       RANK() OVER (ORDER BY salary) AS salary_rank,
       DENSE_RANK() OVER (ORDER BY salary) AS dense_rank,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile
FROM employee_salaries;

```

## 9. MaxCompute 特有注意事项


 WM_CONCAT 字符串聚合（用于会话路径等场景）: 无序!
 按扫描量计费: 窗口函数需要扫描分区内全部数据
 分布式执行: PARTITION BY 利用多 Reducer 并行
 无 PARTITION BY: 单 Reducer 瓶颈 — 避免全局窗口
 支持 PERCENTILE/MEDIAN: 比用窗口函数模拟更直接

## 10. 对引擎开发者的启示


1. 窗口函数是 OLAP 分析的核心基础设施 — 必须高效实现

2. 会话化分析是最复杂但最实用的窗口函数应用 — 值得优化

3. 同比/环比（LAG offset=12/1）是最常见的业务分析需求

4. WM_CONCAT 字符串聚合应支持 ORDER BY（路径分析需要有序）

5. PERCENTILE 作为聚合函数比 PERCENT_RANK 窗口函数更直接

6. QUALIFY 语法可以显著简化窗口函数的过滤场景

