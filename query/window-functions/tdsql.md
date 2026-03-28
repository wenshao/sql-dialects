# TDSQL: 窗口函数

TDSQL distributed MySQL 8.0 compatible.

> 参考资料:
> - [TDSQL-C MySQL Documentation](https://cloud.tencent.com/document/product/1003)
> - [TDSQL MySQL Documentation](https://cloud.tencent.com/document/product/557)


## ROW_NUMBER / RANK / DENSE_RANK

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK()       OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;
```

## 分区

```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;
```

## 聚合窗口函数

```sql
SELECT username, age,
    SUM(age)   OVER () AS total_age,
    AVG(age)   OVER () AS avg_age,
    COUNT(*)   OVER () AS total_count,
    MIN(age)   OVER (PARTITION BY city) AS city_min_age,
    MAX(age)   OVER (PARTITION BY city) AS city_max_age
FROM users;
```

## 偏移函数

```sql
SELECT username, age,
    LAG(age, 1)  OVER (ORDER BY id) AS prev_age,
    LEAD(age, 1) OVER (ORDER BY id) AS next_age,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username)  OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;
```

## NTH_VALUE

```sql
SELECT username, age,
    NTH_VALUE(username, 2) OVER (ORDER BY age) AS second_youngest
FROM users;
```

## NTILE

```sql
SELECT username, age,
    NTILE(4) OVER (ORDER BY age) AS quartile
FROM users;
```

## PERCENT_RANK / CUME_DIST

```sql
SELECT username, age,
    PERCENT_RANK() OVER (ORDER BY age) AS pct_rank,
    CUME_DIST()    OVER (ORDER BY age) AS cume_dist
FROM users;
```

## 命名窗口

```sql
SELECT username, age,
    ROW_NUMBER() OVER w AS rn,
    RANK()       OVER w AS rnk,
    LAG(age)     OVER w AS prev_age
FROM users
WINDOW w AS (ORDER BY age);
```

## 帧子句

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;
```

注意事项：
窗口函数在分布式环境下需要全局排序和聚合
PARTITION BY 如果对齐 shardkey 则性能更好
不带 PARTITION BY 的窗口函数需要全量数据汇聚
