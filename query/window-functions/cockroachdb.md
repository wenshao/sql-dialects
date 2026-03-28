# CockroachDB: 窗口函数

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

```

PARTITION BY
```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

```

Aggregate window functions
```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;

```

LAG / LEAD
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

Named window (WINDOW clause)
```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);

```

Frame clauses (ROWS)
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;

```

Frame clauses (RANGE)
```sql
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM users;

```

GROUPS frame mode (v21.2+)
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS group_sum
FROM users;

```

FILTER clause (v22.1+)
```sql
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) OVER (PARTITION BY city) AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) OVER (PARTITION BY city) AS senior_count
FROM users;

```

Deduplication pattern (keep first per group)
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) WHERE rn = 1;

```

Note: All PostgreSQL window functions supported
Note: GROUPS frame mode supported (v21.2+)
Note: FILTER clause supported (v22.1+)
Note: Window functions work across distributed data
Note: Named WINDOW clause supported
