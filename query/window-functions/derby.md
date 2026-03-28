# Derby: 窗口函数

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)


## Derby 10.11+ 支持有限的窗口函数

ROW_NUMBER（最常用）

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn
FROM users;
```

## RANK / DENSE_RANK（10.11+）

```sql
SELECT username, age,
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

## 聚合窗口函数（10.11+）

```sql
SELECT username, age,
    SUM(age) OVER () AS total_age,
    AVG(age) OVER () AS avg_age,
    COUNT(*) OVER () AS total_count
FROM users;
```

## 带分区的聚合

```sql
SELECT username, city, age,
    AVG(age) OVER (PARTITION BY city) AS city_avg_age,
    MAX(age) OVER (PARTITION BY city) AS city_max_age
FROM users;
```

## 分页查询（使用 ROW_NUMBER）


```sql
SELECT * FROM (
    SELECT username, age,
        ROW_NUMBER() OVER (ORDER BY age) AS rn
    FROM users
) t WHERE rn BETWEEN 11 AND 20;
```

## 取每组第一条

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY created_at DESC) AS rn
    FROM users
) t WHERE rn = 1;
```

## 不支持的窗口函数


不支持 LAG / LEAD
不支持 FIRST_VALUE / LAST_VALUE
不支持 NTH_VALUE
不支持 NTILE
不支持 PERCENT_RANK / CUME_DIST
不支持帧子句（ROWS BETWEEN ... AND ...）
不支持命名窗口（WINDOW w AS ...）
不支持 FILTER 子句

## LAG/LEAD 替代方案（使用自连接）


## 模拟 LAG（获取前一行的值）

```sql
SELECT a.username, a.age,
    b.age AS prev_age
FROM (SELECT username, age, ROW_NUMBER() OVER (ORDER BY age) AS rn FROM users) a
LEFT OUTER JOIN
    (SELECT age, ROW_NUMBER() OVER (ORDER BY age) AS rn FROM users) b
ON a.rn = b.rn + 1;
```

注意：Derby 的窗口函数支持非常有限
注意：仅支持 ROW_NUMBER, RANK, DENSE_RANK 和基本聚合
注意：不支持 LAG/LEAD 等偏移函数
注意：不支持帧子句和命名窗口
注意：10.11 之前的版本窗口函数更加有限
