# BigQuery: 窗口函数

> 参考资料:
> - [1] BigQuery SQL Reference - Window Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls
> - [2] BigQuery SQL Reference - Navigation Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/navigation_functions


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
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM users;

```

分析函数用于去重（取每组第一条）

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) WHERE rn = 1;

```

QUALIFY（2023+ 支持，直接过滤窗口函数结果）

```sql
SELECT username, city, age
FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) = 1;

```

注意：BigQuery 窗口函数支持完善，语法符合 SQL 标准
注意：BigQuery 2023+ 支持 QUALIFY 子句
注意：BigQuery 不支持 GROUPS 帧模式
注意：BigQuery 不支持 FILTER 子句

