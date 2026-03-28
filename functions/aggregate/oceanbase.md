# OceanBase: 聚合函数

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL)


Basic aggregates
```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

```

GROUP BY
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

```

GROUP BY + HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

```

WITH ROLLUP
```sql
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

```

GROUP_CONCAT
```sql
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;

```

JSON aggregation
```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

```

Statistical functions
```sql
SELECT STD(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;

```

## Oracle Mode


Basic aggregates (same syntax)
```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

```

GROUP BY
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

```

HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

```

ROLLUP (Oracle syntax, no WITH keyword)
```sql
SELECT city, COUNT(*) FROM users GROUP BY ROLLUP(city);

```

CUBE (Oracle mode, not available in MySQL mode)
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE(city, status);

```

GROUPING SETS (Oracle mode, not available in MySQL mode)
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS (
    (city),
    (status),
    (city, status),
    ()
);

```

GROUPING function (use with ROLLUP/CUBE/GROUPING SETS)
```sql
SELECT city, COUNT(*), GROUPING(city) AS is_total
FROM users
GROUP BY ROLLUP(city);

```

LISTAGG (Oracle mode, equivalent to GROUP_CONCAT)
```sql
SELECT city, LISTAGG(username, ', ') WITHIN GROUP (ORDER BY username)
FROM users
GROUP BY city;

```

KEEP (DENSE_RANK FIRST/LAST) (Oracle mode)
```sql
SELECT city,
    MIN(age) KEEP (DENSE_RANK FIRST ORDER BY created_at) AS earliest_user_age,
    MAX(age) KEEP (DENSE_RANK LAST ORDER BY created_at) AS latest_user_age
FROM users
GROUP BY city;

```

MEDIAN (Oracle mode)
```sql
SELECT city, MEDIAN(age) FROM users GROUP BY city;

```

PERCENTILE_CONT / PERCENTILE_DISC (Oracle mode)
```sql
SELECT city,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) AS median_age,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) AS median_disc
FROM users
GROUP BY city;

```

STATS_MODE (Oracle mode, return most frequent value)
Limited support in OceanBase

Parallel aggregation hint
```sql
SELECT /*+ PARALLEL(4) */ city, SUM(amount)
FROM orders
GROUP BY city;

```

Limitations:
MySQL mode: same as MySQL (no CUBE, GROUPING SETS)
Oracle mode: CUBE, GROUPING SETS, ROLLUP all supported
Oracle mode: LISTAGG, KEEP, MEDIAN, PERCENTILE functions
Oracle mode: GROUPING function for rollup/cube queries
Aggregate parallelism depends on cluster resources
