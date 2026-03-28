# Trino: 窗口函数

> 参考资料:
> - [Trino - Window Functions](https://trino.io/docs/current/functions/window.html)
> - [Trino - Functions and Operators](https://trino.io/docs/current/functions.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

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

GROUPS 帧
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS group_sum
FROM users;

```

FILTER（聚合函数过滤）
```sql
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) OVER () AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) OVER () AS senior_count
FROM users;

```

窗口函数去重
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE rn = 1;

```

**注意:** Trino 窗口函数支持非常完善，高度符合 SQL 标准
**注意:** Trino 支持 ROWS / RANGE / GROUPS 三种帧模式
**注意:** Trino 支持 FILTER 子句
**注意:** 窗口函数性能取决于底层连接器
