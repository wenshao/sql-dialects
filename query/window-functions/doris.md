# Apache Doris: 窗口函数

 Apache Doris: 窗口函数

 参考资料:
   [1] Doris Documentation - Window Functions
       https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/

## 1. 排名函数

```sql
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK() OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

```

分区排名

```sql
SELECT username, city, age,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS city_rank
FROM users;

```

## 2. 聚合窗口

```sql
SELECT username, age,
    SUM(age) OVER () AS total, AVG(age) OVER () AS avg_age,
    MIN(age) OVER (PARTITION BY city) AS city_min,
    MAX(age) OVER (PARTITION BY city) AS city_max
FROM users;

```

## 3. 偏移函数

```sql
SELECT username, age,
    LAG(age, 1) OVER (ORDER BY id) AS prev,
    LEAD(age, 1) OVER (ORDER BY id) AS next,
    FIRST_VALUE(username) OVER (PARTITION BY city ORDER BY age) AS youngest,
    LAST_VALUE(username) OVER (PARTITION BY city ORDER BY age
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS oldest
FROM users;

SELECT username, NTH_VALUE(username, 2) OVER (ORDER BY age) AS second FROM users;
SELECT username, NTILE(4) OVER (ORDER BY age) AS quartile FROM users;

```

## 4. 分布函数

```sql
SELECT username, PERCENT_RANK() OVER (ORDER BY age) AS pct,
    CUME_DIST() OVER (ORDER BY age) AS cume FROM users;

```

## 5. 命名窗口

```sql
SELECT username, ROW_NUMBER() OVER w AS rn, RANK() OVER w AS rnk
FROM users WINDOW w AS (ORDER BY age);

```

## 6. 帧子句

```sql
SELECT username,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling,
    AVG(age) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS moving
FROM users;

```

RANGE 帧

```sql
SELECT username, COUNT(*) OVER (ORDER BY age RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING) FROM users;

```

限制: 不支持 QUALIFY(StarRocks 3.2+)、GROUPS 帧、FILTER 子句。

