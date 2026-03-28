# SQL 标准: 窗口函数实战分析

> 参考资料:
> - [ISO/IEC 9075 SQL Standard - Window Functions (SQL:2003 引入)](https://en.wikipedia.org/wiki/SQL:2003)
> - [SQL Standard - OLAP Functions](https://en.wikipedia.org/wiki/SQL_window_function)

## 示例数据上下文

假设表结构:
  daily_sales(sale_date DATE, product_id INT, region VARCHAR,
              amount DECIMAL(10,2), quantity INT)
  user_events(user_id INT, event_time TIMESTAMP, event_type VARCHAR,
              page VARCHAR, session_id VARCHAR)
  employee_salaries(emp_id INT, department VARCHAR, salary DECIMAL(10,2),
                    hire_date DATE)

## 1. 移动平均（Moving Average）

3 天移动平均
```sql
SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ) AS ma_3d
FROM daily_sales;
```

7 天移动平均
```sql
SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY sale_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ) AS ma_7d
FROM daily_sales;
```

30 天移动平均（按日期范围）
```sql
SELECT sale_date, amount,
       AVG(amount) OVER (
           ORDER BY sale_date
           RANGE BETWEEN INTERVAL '29' DAY PRECEDING AND CURRENT ROW
       ) AS ma_30d
FROM daily_sales;
```

## 2. 同比/环比（Year-over-Year / Month-over-Month）

环比（Month-over-Month）: 与上月相比
```sql
SELECT sale_month, total_amount,
       LAG(total_amount, 1) OVER (ORDER BY sale_month) AS prev_month,
       (total_amount - LAG(total_amount, 1) OVER (ORDER BY sale_month))
           / LAG(total_amount, 1) OVER (ORDER BY sale_month) * 100
           AS mom_pct
FROM (
    SELECT EXTRACT(YEAR FROM sale_date) * 100 + EXTRACT(MONTH FROM sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY EXTRACT(YEAR FROM sale_date) * 100 + EXTRACT(MONTH FROM sale_date)
) monthly;
```

同比（Year-over-Year）: 与去年同期相比
```sql
SELECT sale_month, total_amount,
       LAG(total_amount, 12) OVER (ORDER BY sale_month) AS prev_year,
       (total_amount - LAG(total_amount, 12) OVER (ORDER BY sale_month))
           / LAG(total_amount, 12) OVER (ORDER BY sale_month) * 100
           AS yoy_pct
FROM (
    SELECT EXTRACT(YEAR FROM sale_date) * 100 + EXTRACT(MONTH FROM sale_date) AS sale_month,
           SUM(amount) AS total_amount
    FROM daily_sales
    GROUP BY EXTRACT(YEAR FROM sale_date) * 100 + EXTRACT(MONTH FROM sale_date)
) monthly;
```

## 3. 占比（Percentage of Total）

每个产品占总销售额的百分比
```sql
SELECT product_id, SUM(amount) AS product_total,
       SUM(amount) / SUM(SUM(amount)) OVER () * 100 AS pct_of_total
FROM daily_sales
GROUP BY product_id;
```

每个产品在其所属区域内的占比
```sql
SELECT region, product_id, SUM(amount) AS product_total,
       SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY region) * 100
           AS pct_within_region
FROM daily_sales
GROUP BY region, product_id;
```

## 4. 百分位数 / 中位数（Percentile / Median）

SQL 标准定义的百分位函数
```sql
SELECT department,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary) AS p25,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary) AS p75,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY salary) AS p90,
       PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY salary) AS p99
FROM employee_salaries
GROUP BY department;
```

PERCENTILE_DISC（离散百分位，返回实际值）
```sql
SELECT department,
       PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY salary) AS median_salary
FROM employee_salaries
GROUP BY department;
```

## 5. 会话化（Sessionization）

按时间间隔将事件分组为会话（间隔 > 30 分钟则新会话）
```sql
WITH event_gaps AS (
    SELECT user_id, event_time, event_type,
           CASE
               WHEN event_time - LAG(event_time) OVER (
                   PARTITION BY user_id ORDER BY event_time
               ) > INTERVAL '30' MINUTE
               THEN 1
               ELSE 0
           END AS new_session
    FROM user_events
),
sessions AS (
    SELECT user_id, event_time, event_type,
           SUM(new_session) OVER (
               PARTITION BY user_id ORDER BY event_time
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS session_id
    FROM event_gaps
)
SELECT user_id, session_id,
       MIN(event_time) AS session_start,
       MAX(event_time) AS session_end,
       COUNT(*) AS event_count
FROM sessions
GROUP BY user_id, session_id;
```

## 6. FIRST_VALUE / LAST_VALUE

每个部门第一个入职的员工薪资
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

- **注意：LAST_VALUE 需要指定完整窗口帧，否则默认只到当前行**

## 7. LEAD / LAG 趋势检测

连续增长检测
```sql
SELECT sale_date, amount,
       LAG(amount, 1) OVER (ORDER BY sale_date) AS prev_day,
       LEAD(amount, 1) OVER (ORDER BY sale_date) AS next_day,
       CASE
           WHEN amount > LAG(amount, 1) OVER (ORDER BY sale_date)
            AND amount > LAG(amount, 2) OVER (ORDER BY sale_date)
           THEN 'uptrend'
           WHEN amount < LAG(amount, 1) OVER (ORDER BY sale_date)
            AND amount < LAG(amount, 2) OVER (ORDER BY sale_date)
           THEN 'downtrend'
           ELSE 'neutral'
       END AS trend
FROM daily_sales;
```

## 8. 累计分布（PERCENT_RANK, CUME_DIST, NTILE）

薪资分布分析
```sql
SELECT emp_id, department, salary,
       PERCENT_RANK() OVER (ORDER BY salary) AS pct_rank,
       CUME_DIST() OVER (ORDER BY salary) AS cum_dist,
       NTILE(4) OVER (ORDER BY salary) AS quartile,
       NTILE(10) OVER (ORDER BY salary) AS decile
FROM employee_salaries;
```

PERCENT_RANK: (rank - 1) / (total_rows - 1)，范围 [0, 1]
CUME_DIST: 累计分布比例，范围 (0, 1]
NTILE(n): 将数据均匀分成 n 组

部门内薪资分布
```sql
SELECT emp_id, department, salary,
       PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) AS dept_pct_rank,
       NTILE(4) OVER (PARTITION BY department ORDER BY salary) AS dept_quartile
FROM employee_salaries;
```

