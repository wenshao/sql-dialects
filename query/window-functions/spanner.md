# Spanner: 窗口函数

> 参考资料:
> - [Spanner SQL Reference (GoogleSQL)](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)
> - [Spanner - Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators)
> - [Spanner - Data Types](https://cloud.google.com/spanner/docs/reference/standard-sql/data-types)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT Username, Age,
    ROW_NUMBER() OVER (ORDER BY Age) AS rn,
    RANK()       OVER (ORDER BY Age) AS rnk,
    DENSE_RANK() OVER (ORDER BY Age) AS dense_rnk
FROM Users;

```

PARTITION BY
```sql
SELECT Username, City, Age,
    ROW_NUMBER() OVER (PARTITION BY City ORDER BY Age DESC) AS city_rank
FROM Users;

```

Aggregate window functions
```sql
SELECT Username, Age,
    SUM(Age)   OVER () AS total_age,
    AVG(Age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(Age)   OVER (PARTITION BY City) AS city_min_age,
    MAX(Age)   OVER (PARTITION BY City) AS city_max_age
FROM Users;

```

LAG / LEAD
```sql
SELECT Username, Age,
    LAG(Age, 1)  OVER (ORDER BY UserId) AS prev_age,
    LEAD(Age, 1) OVER (ORDER BY UserId) AS next_age,
    FIRST_VALUE(Username) OVER (PARTITION BY City ORDER BY Age) AS youngest,
    LAST_VALUE(Username)  OVER (PARTITION BY City ORDER BY Age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM Users;

```

NTH_VALUE
```sql
SELECT Username, Age,
    NTH_VALUE(Username, 2) OVER (ORDER BY Age) AS second_youngest
FROM Users;

```

NTILE
```sql
SELECT Username, Age,
    NTILE(4) OVER (ORDER BY Age) AS quartile
FROM Users;

```

PERCENT_RANK / CUME_DIST
```sql
SELECT Username, Age,
    PERCENT_RANK() OVER (ORDER BY Age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY Age) AS cume_dist
FROM Users;

```

Named window (WINDOW clause)
```sql
SELECT Username, Age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(Age)     OVER w AS prev_age
FROM Users
WINDOW w AS (ORDER BY Age);

```

Frame clauses (ROWS)
```sql
SELECT Username, Age,
    SUM(Age) OVER (ORDER BY UserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(Age) OVER (ORDER BY UserId ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM Users;

```

Frame clauses (RANGE)
```sql
SELECT Username, Age,
    COUNT(*) OVER (ORDER BY Age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM Users;

```

Deduplication pattern (keep first per group)
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY City ORDER BY CreatedAt DESC) AS rn
    FROM Users
) WHERE rn = 1;

```

Running total
```sql
SELECT OrderId, Amount,
    SUM(Amount) OVER (ORDER BY OrderDate ROWS UNBOUNDED PRECEDING) AS running_total
FROM Orders;

```

Note: Most SQL standard window functions are supported
Note: GROUPS frame mode is not supported
Note: FILTER clause is not supported
Note: Named WINDOW clause is supported
Note: Window functions are executed on Spanner's distributed compute nodes
