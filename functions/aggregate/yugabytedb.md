# YugabyteDB: 聚合函数

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

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

GROUPING SETS
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

```

ROLLUP
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

```

CUBE
```sql
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

```

GROUPING() function
```sql
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

```

String aggregation
```sql
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT STRING_AGG(DISTINCT city, ', ') FROM users;

```

JSON aggregation
```sql
SELECT JSON_AGG(username) FROM users;
SELECT JSONB_AGG(username) FROM users;
SELECT JSON_OBJECT_AGG(username, age) FROM users;
SELECT JSONB_OBJECT_AGG(username, age) FROM users;

```

Array aggregation
```sql
SELECT ARRAY_AGG(username ORDER BY username) FROM users;
SELECT ARRAY_AGG(DISTINCT city) FROM users;

```

Statistical functions
```sql
SELECT STDDEV(amount) FROM orders;                     -- sample std dev
SELECT STDDEV_POP(amount) FROM orders;                 -- population std dev
SELECT VARIANCE(amount) FROM orders;                   -- sample variance
SELECT VAR_POP(amount) FROM orders;                    -- population variance
SELECT CORR(x, y) FROM data;                          -- correlation
SELECT COVAR_SAMP(x, y) FROM data;                    -- sample covariance
SELECT REGR_SLOPE(y, x) FROM data;                    -- linear regression slope

```

FILTER clause (conditional aggregation)
```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior
FROM users;

```

Boolean aggregates
```sql
SELECT BOOL_AND(active) FROM users;
SELECT BOOL_OR(active) FROM users;
SELECT EVERY(active) FROM users;                       -- same as BOOL_AND

```

BIT aggregates
```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;

```

Note: All PostgreSQL aggregate functions supported
Note: FILTER clause supported for conditional aggregation
Note: GROUPING SETS, ROLLUP, CUBE all supported
Note: Aggregations work across distributed tablets
Note: Based on PostgreSQL 11.2 aggregate function set
Note: Pushdown optimizations for aggregates on distributed data
