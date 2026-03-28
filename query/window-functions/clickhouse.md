# ClickHouse: 窗口函数（21.1+）

> 参考资料:
> - [1] ClickHouse SQL Reference - Window Functions
>   https://clickhouse.com/docs/en/sql-reference/window-functions
> - [2] ClickHouse SQL Reference - SELECT
>   https://clickhouse.com/docs/en/sql-reference/statements/select


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
    lagInFrame(age, 1)  OVER (ORDER BY id) AS prev_age,
    leadInFrame(age, 1) OVER (ORDER BY id) AS next_age,
    first_value(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    last_value(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

```

也支持标准 LAG / LEAD（22.8+）

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age
FROM users;

```

NTH_VALUE（22.8+）

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

帧子句

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

```

LIMIT BY（ClickHouse 特有，类似 PARTITION 级别的 LIMIT）

```sql
SELECT username, city, age
FROM users
ORDER BY city, age DESC
LIMIT 3 BY city;

```

LIMIT BY + OFFSET

```sql
SELECT username, city, age
FROM users
ORDER BY city, age DESC
LIMIT 2, 3 BY city;    -- 每个 city 跳过前 2 条取 3 条

```

窗口函数去重

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) WHERE rn = 1;

```

注意：ClickHouse 21.1 起支持窗口函数，之前版本需使用其他方式实现
注意：ClickHouse 早期窗口函数实现使用 lagInFrame / leadInFrame 函数名
注意：ClickHouse 不支持 GROUPS 帧模式
注意：ClickHouse 不支持 FILTER 子句
注意：LIMIT BY 是 ClickHouse 独特的替代方案，可代替部分窗口函数使用场景

