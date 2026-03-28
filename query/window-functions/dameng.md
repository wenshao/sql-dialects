# DamengDB (达梦): 窗口函数

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)


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

## RATIO_TO_REPORT（Oracle 分析函数）

```sql
SELECT username, age,
    RATIO_TO_REPORT(age) OVER () AS age_ratio
FROM users;
```

## LISTAGG（Oracle 字符串聚合窗口函数）

```sql
SELECT city,
    LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username) OVER (PARTITION BY city) AS user_list
FROM users;
```

## 帧子句

```sql
SELECT username, age,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_sum,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving_avg
FROM users;
```

注意事项：
语法与 Oracle 兼容
支持 RATIO_TO_REPORT 等 Oracle 特有分析函数
支持 LISTAGG 字符串聚合
支持所有 SQL 标准窗口函数
