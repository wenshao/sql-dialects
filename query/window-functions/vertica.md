# Vertica: 窗口函数

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


ROW_NUMBER / RANK / DENSE_RANK
```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;
```


分区
```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
```


聚合窗口函数
```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;
```


偏移函数
```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```


NTH_VALUE
```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;
```


NTILE
```sql
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;
```


PERCENT_RANK / CUME_DIST
```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;
```


命名窗口
```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);
```


帧子句
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;
```


RANGE 帧
```sql
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS nearby_count
FROM users;
```


MEDIAN（Vertica 特有的分析函数）
```sql
SELECT city,
    MEDIAN(age) OVER (PARTITION BY city) AS median_age
FROM users;
```


PERCENTILE_CONT / PERCENTILE_DISC
```sql
SELECT city, age,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS p50,
    PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY age) OVER (PARTITION BY city) AS p95
FROM users;
```


CONDITIONAL_TRUE_EVENT / CONDITIONAL_CHANGE_EVENT
```sql
SELECT username, status,
    CONDITIONAL_CHANGE_EVENT(status) OVER (ORDER BY id) AS change_seq
FROM users;
```


指数移动平均（Vertica 分析特有）
```sql
SELECT ts, value,
    EXPONENTIAL_MOVING_AVERAGE(value, 0.3) OVER (ORDER BY ts) AS ema
FROM sensor_data;
```


窗口函数去重
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE rn = 1;
```


注意：Vertica 窗口函数支持非常丰富
注意：支持 MEDIAN, PERCENTILE_CONT/DISC 等高级分析函数
注意：支持 CONDITIONAL_CHANGE_EVENT 等会话化函数
注意：支持 EXPONENTIAL_MOVING_AVERAGE 等时间序列函数
注意：支持命名窗口
