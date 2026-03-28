# Hive: 窗口函数实战分析 (Window Analytics)

> 参考资料:
> - [1] Apache Hive - Windowing and Analytics Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics


## 1. 移动平均 (Moving Average)

```sql
SELECT sale_date, amount,
    ROUND(AVG(amount) OVER (ORDER BY sale_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma_3d,
    ROUND(AVG(amount) OVER (ORDER BY sale_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d,
    ROUND(AVG(amount) OVER (ORDER BY sale_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 2) AS ma_30d
FROM daily_sales;

```

按产品分组

```sql
SELECT sale_date, product_id, amount,
    ROUND(AVG(amount) OVER (PARTITION BY product_id
        ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d
FROM daily_sales;

```

## 2. 同比/环比

```sql
SELECT sale_date, amount,
    LAG(amount, 1)   OVER (ORDER BY sale_date) AS prev_day,
    LAG(amount, 7)   OVER (ORDER BY sale_date) AS prev_week,
    LAG(amount, 365) OVER (ORDER BY sale_date) AS prev_year,
    ROUND((amount - LAG(amount, 1) OVER (ORDER BY sale_date))
        / LAG(amount, 1) OVER (ORDER BY sale_date) * 100, 2) AS dod_pct,
    ROUND((amount - LAG(amount, 7) OVER (ORDER BY sale_date))
        / LAG(amount, 7) OVER (ORDER BY sale_date) * 100, 2) AS wow_pct
FROM daily_sales;

```

## 3. 累计占比与 Pareto 分析

```sql
SELECT product_id, total_amount,
    SUM(total_amount) OVER (ORDER BY total_amount DESC) AS cumulative,
    ROUND(SUM(total_amount) OVER (ORDER BY total_amount DESC)
        / SUM(total_amount) OVER () * 100, 2) AS cumulative_pct
FROM (
    SELECT product_id, SUM(amount) AS total_amount
    FROM daily_sales GROUP BY product_id
) agg;

```

## 4. 会话分析 (Session Analysis)

将用户事件按 30 分钟间隔分割为会话

```sql
SELECT user_id, event_time, event_type,
    SUM(new_session) OVER (PARTITION BY user_id ORDER BY event_time) AS session_id
FROM (
    SELECT user_id, event_time, event_type,
        CASE WHEN UNIX_TIMESTAMP(event_time) - LAG(UNIX_TIMESTAMP(event_time))
            OVER (PARTITION BY user_id ORDER BY event_time) > 1800
            OR LAG(event_time) OVER (PARTITION BY user_id ORDER BY event_time) IS NULL
        THEN 1 ELSE 0 END AS new_session
    FROM user_events
) t;

```

## 5. 薪资分位数与排名

```sql
SELECT emp_id, department, salary,
    NTILE(4) OVER (PARTITION BY department ORDER BY salary) AS salary_quartile,
    PERCENT_RANK() OVER (PARTITION BY department ORDER BY salary) AS pct_rank,
    salary - AVG(salary) OVER (PARTITION BY department) AS diff_from_avg,
    salary / AVG(salary) OVER (PARTITION BY department) AS ratio_to_avg
FROM employee_salaries;

```

## 6. 连续事件检测 (Streak Detection)

检测连续增长天数

```sql
SELECT sale_date, amount, streak_group,
    COUNT(*) OVER (PARTITION BY streak_group) AS streak_length
FROM (
    SELECT sale_date, amount,
        SUM(CASE WHEN amount > prev_amount THEN 0 ELSE 1 END)
            OVER (ORDER BY sale_date) AS streak_group
    FROM (
        SELECT sale_date, amount,
            LAG(amount) OVER (ORDER BY sale_date) AS prev_amount
        FROM daily_sales
    ) t
) t2;

```

## 7. 首次/最后一次事件

```sql
SELECT user_id,
    FIRST_VALUE(event_time) OVER (PARTITION BY user_id ORDER BY event_time) AS first_visit,
    LAST_VALUE(event_time) OVER (PARTITION BY user_id ORDER BY event_time
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_visit,
    DATEDIFF(
        LAST_VALUE(event_time) OVER (PARTITION BY user_id ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
        FIRST_VALUE(event_time) OVER (PARTITION BY user_id ORDER BY event_time)
    ) AS active_days
FROM user_events;

```

## 8. 对引擎开发者的启示

### 1. 窗口函数是数据分析的核心: 移动平均、同比环比、累计占比都依赖窗口函数

### 2. 会话分析是窗口函数的经典应用: LAG + 条件 SUM 实现会话分割

### 3. LAST_VALUE 默认帧陷阱需要在文档中突出: 这是最常见的窗口函数错误

### 4. 多个窗口函数共享 PARTITION BY + ORDER BY 时可以合并排序:

优化器应该识别并复用排序结果

