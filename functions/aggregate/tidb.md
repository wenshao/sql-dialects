# TiDB: 聚合函数

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

```

GROUP BY (same as MySQL)
```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

```

GROUP BY + HAVING (same as MySQL)
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;

```

WITH ROLLUP (same as MySQL)
```sql
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;

```

GROUP_CONCAT (same as MySQL)
```sql
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

```

JSON aggregation (same as MySQL 5.7.22+)
```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;

```

Statistical functions (same as MySQL)
```sql
SELECT STD(amount) FROM orders;
SELECT STDDEV(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;

```

BIT aggregates (same as MySQL)
```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;

```

TiDB-specific: aggregate pushdown to TiKV
TiDB pushes aggregate operations to TiKV coprocessor
This reduces data transfer between TiKV and TiDB
Controlled by tidb_opt_agg_push_down (default: OFF)
```sql
SET tidb_opt_agg_push_down = ON;

```

TiDB-specific: aggregate pushdown to TiFlash (5.0+)
When TiFlash replicas exist, aggregates can be computed in MPP mode
Parallel execution across TiFlash nodes
```sql
SELECT /*+ READ_FROM_STORAGE(TIFLASH[orders]) */ city, SUM(amount)
FROM users u JOIN orders o ON u.id = o.user_id
GROUP BY city;

```

TiDB-specific: APPROX_COUNT_DISTINCT (approximate count distinct)
Faster than exact COUNT(DISTINCT) for large datasets
Uses HyperLogLog algorithm
```sql
SELECT APPROX_COUNT_DISTINCT(city) FROM users;

```

TiDB-specific: APPROX_PERCENTILE (5.0+)
Approximate percentile calculation for large datasets
```sql
SELECT APPROX_PERCENTILE(age, 50) FROM users;    -- median
SELECT APPROX_PERCENTILE(amount, 95) FROM orders; -- p95
SELECT APPROX_PERCENTILE(amount, 99) FROM orders; -- p99

```

Hash aggregate vs Stream aggregate
TiDB automatically chooses between hash and stream aggregation
Can force with hints:
```sql
SELECT /*+ HASH_AGG() */ city, COUNT(*) FROM users GROUP BY city;
SELECT /*+ STREAM_AGG() */ city, COUNT(*) FROM users GROUP BY city;

```

GROUPING SETS: not directly supported (same as MySQL)
Simulate with UNION ALL:
```sql
SELECT city, NULL AS status, COUNT(*) FROM users GROUP BY city
UNION ALL
SELECT NULL, status, COUNT(*) FROM users GROUP BY status;

```

Limitations:
No GROUPING SETS, CUBE, or ROLLUP with multiple grouping sets
APPROX_COUNT_DISTINCT has ~0.8% error rate
GROUP_CONCAT max length controlled by group_concat_max_len
Aggregate pushdown requires compatible expressions
Memory consumption for aggregation may differ from MySQL
