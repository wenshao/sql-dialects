# DuckDB: 窗口分析实战

> 参考资料:
> - [DuckDB Documentation - Window Functions](https://duckdb.org/docs/sql/window_functions)
> - [DuckDB Documentation - Aggregate Functions](https://duckdb.org/docs/sql/aggregates)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 假设表结构:

  daily_sales(sale_date DATE, product_id INTEGER, region VARCHAR,
              amount DECIMAL(10,2), quantity INTEGER)
  user_events(user_id INTEGER, event_time TIMESTAMP, event_type VARCHAR,
              page VARCHAR)
  employee_salaries(emp_id INTEGER, department VARCHAR, salary DECIMAL(10,2),
                    hire_date DATE)

## 移动平均（Moving Average）


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

30 天移动平均（DuckDB 支持 RANGE + INTERVAL）
```sql
SELECT sale_date, amount,
       ROUND(AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL 29 DAY PRECEDING AND CURRENT ROW
       ), 2) AS ma_30d
FROM daily_sales;

```

## 同比/环比（YoY / MoM）


```sql
WITH monthly AS (
    SELECT DATE_TRUNC('month', sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY sale_month
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

## 占比（Percentage of Total）


```sql
SELECT product_id,
       SUM(amount) AS product_total,
       ROUND(SUM(amount) / SUM(SUM(amount)) OVER () * 100, 2) AS pct_of_total
FROM daily_sales
GROUP BY product_id
ORDER BY pct_of_total DESC;

```

## 百分位数 / 中位数


DuckDB 支持标准 PERCENTILE_CONT
```sql
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90,
       MEDIAN(salary) AS median_builtin          -- DuckDB 内置 MEDIAN
FROM employee_salaries
GROUP BY department;

```

近似百分位
```sql
SELECT department,
       APPROX_QUANTILE(salary, 0.5) AS approx_median,
       RESERVOIR_QUANTILE(salary, 0.5) AS reservoir_median
FROM employee_salaries
GROUP BY department;

```

## 会话化（Sessionization）


```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) > INTERVAL 30 MINUTE
               OR LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) IS NULL
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
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       DATE_DIFF('second', MIN(event_time), MAX(event_time)) AS duration_sec,
       COUNT(*) AS event_count,
       LIST(event_type ORDER BY event_time) AS event_path,
       LIST(DISTINCT page) AS pages_visited
FROM sessions
GROUP BY user_id, session_num;

```

## FIRST_VALUE / LAST_VALUE


```sql
SELECT emp_id, department, salary, hire_date,
       FIRST_VALUE(salary) OVER w AS first_hire_salary,
       LAST_VALUE(salary) OVER (
           PARTITION BY department ORDER BY hire_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_hire_salary,
       NTH_VALUE(salary, 2) OVER (
           PARTITION BY department ORDER BY salary DESC
           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS second_highest
FROM employee_salaries
WINDOW w AS (PARTITION BY department ORDER BY hire_date);

```

## LEAD / LAG 趋势检测


```sql
SELECT sale_date, amount,
       LAG(amount) OVER w AS prev_day,
       LEAD(amount) OVER w AS next_day,
       amount - LAG(amount) OVER w AS daily_change,
       ROUND((amount - LAG(amount) OVER w)
           / NULLIF(LAG(amount) OVER w, 0) * 100, 2) AS change_pct
FROM daily_sales
WINDOW w AS (ORDER BY sale_date);

```

## 累计分布（PERCENT_RANK, CUME_DIST, NTILE）


```sql
SELECT emp_id, department, salary,
       RANK() OVER w AS salary_rank,
       DENSE_RANK() OVER w AS dense_rank,
       ROUND(PERCENT_RANK() OVER w, 4) AS pct_rank,
       ROUND(CUME_DIST() OVER w, 4) AS cum_dist,
       NTILE(4) OVER w AS quartile,
       NTILE(10) OVER w AS decile
FROM employee_salaries
WINDOW w AS (ORDER BY salary);

```

DuckDB 窗口函数完整支持：
所有 SQL 标准窗口函数
RANGE + INTERVAL 帧
WINDOW 子句（命名窗口）
GROUPS 帧类型
EXCLUDE 子句
QUALIFY 子句（直接过滤窗口函数结果）
```sql
SELECT emp_id, department, salary,
       RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS dept_rank
FROM employee_salaries
QUALIFY dept_rank <= 3;                         -- DuckDB 支持 QUALIFY

```
