# Spark SQL: 窗口函数实战分析 (Window Analytics)

> 参考资料:
> - [1] Spark SQL - Window Functions
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html


## 1. 移动平均（Moving Average）

```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 2) AS ma_3d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS ma_7d,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

```

## 2. 同比/环比（MoM / YoY）

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

## 3. 占比分析

```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

```

## 4. 百分位数与中位数

```sql
SELECT department,
       PERCENTILE_APPROX(salary, 0.5) AS median_salary,
       PERCENTILE_APPROX(salary, ARRAY(0.25, 0.5, 0.75, 0.9, 0.99)) AS percentiles,
       PERCENTILE(salary, 0.5) AS exact_median
FROM employee_salaries
GROUP BY department;

```

 PERCENTILE_APPROX vs PERCENTILE:
   PERCENTILE_APPROX: 近似算法，适合大数据集（内存 O(1)）
   PERCENTILE:        精确计算，需要全量排序（内存 O(n)）
   BigQuery 和 Snowflake 使用 APPROX_QUANTILES 提供类似功能

## 5. 会话化分析（Sessionization）

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
       COLLECT_LIST(event_type) AS event_path
FROM sessions
GROUP BY user_id, session_num;

```

 会话化是 Spark SQL 的经典用例:
   30 分钟无活动 = 新会话（可配置阈值）
   COLLECT_LIST(event_type) 收集用户行为路径——Spark 独有能力

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

## 7. LAG / LEAD 变化检测

```sql
SELECT sale_date, amount,
       LAG(amount, 1, 0) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1, 0) OVER (ORDER BY sale_date) AS next_day,
       amount - LAG(amount) OVER (ORDER BY sale_date) AS daily_change
FROM daily_sales;

```

## 8. 累计分布

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

## 9. 命名窗口简化复杂查询

```sql
SELECT sale_date, amount,
       SUM(amount) OVER w AS running_total,
       AVG(amount) OVER w AS running_avg,
       COUNT(*) OVER w AS running_count
FROM daily_sales
WINDOW w AS (ORDER BY sale_date ROWS UNBOUNDED PRECEDING);

```

## 10. 版本演进

Spark 1.4: 基本窗口函数
Spark 3.0: 命名窗口 (WINDOW w AS), GROUPS 帧
Spark 3.1: NTH_VALUE
Spark 3.3: 窗口函数性能优化

Spark 窗口函数的核心特色:
COLLECT_LIST/COLLECT_SET 可在窗口函数上下文中使用（聚合为数组）
PERCENTILE_APPROX 适合 TB 级数据的近似分位数计算
分布式执行: PARTITION BY 决定 Shuffle，应尽量使用

