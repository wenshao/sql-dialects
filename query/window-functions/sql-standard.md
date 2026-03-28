# SQL 标准: 窗口函数

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - Window Functions](https://modern-sql.com/feature/over-and-partition-by)

## SQL:2003

首次引入窗口函数

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

命名窗口（WINDOW 子句）
```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);
```

帧子句 - ROWS
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sum
FROM users;
```

帧子句 - RANGE
```sql
SELECT username, age,
    COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS age_range_count
FROM users;
```

帧边界选项：
UNBOUNDED PRECEDING: 分区第一行
n PRECEDING: 当前行前 n 行/值
CURRENT ROW: 当前行
n FOLLOWING: 当前行后 n 行/值
UNBOUNDED FOLLOWING: 分区最后一行

## SQL:2008

无窗口函数相关新增

## SQL:2011

GROUPS 帧模式（第三种帧模式）
```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY age GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS group_sum
FROM users;
```

ROWS: 按物理行偏移
RANGE: 按值范围偏移
GROUPS: 按同值组（peer group）偏移

FILTER 子句（聚合函数级别的条件过滤）
```sql
SELECT city,
    COUNT(*) FILTER (WHERE age < 30) OVER () AS young_count,
    COUNT(*) FILTER (WHERE age >= 30) OVER () AS senior_count
FROM users;
```

帧排除选项（EXCLUDE）
```sql
SELECT username, age,
    AVG(age) OVER (ORDER BY age
        ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        EXCLUDE CURRENT ROW) AS avg_without_self
FROM users;
```

EXCLUDE CURRENT ROW: 排除当前行
EXCLUDE GROUP: 排除当前行及所有同值行
EXCLUDE TIES: 排除同值行但保留当前行
EXCLUDE NO OTHERS: 不排除（默认）

各标准版本窗口函数特性总结：
SQL:2003: ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD,
          FIRST_VALUE, LAST_VALUE, NTH_VALUE, PERCENT_RANK, CUME_DIST,
          聚合窗口函数, WINDOW 子句, ROWS/RANGE 帧
SQL:2011: GROUPS 帧模式, FILTER 子句, EXCLUDE 选项
