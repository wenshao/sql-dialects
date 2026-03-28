# TiDB: 子查询

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE subquery (same as MySQL)
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

```

EXISTS (same as MySQL)
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

FROM subquery / derived table (same as MySQL)
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

LATERAL derived table (7.0+, same as MySQL 8.0)
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

Subquery optimization differences:
TiDB's optimizer handles subqueries differently from MySQL
Semi-join optimization for IN/EXISTS subqueries
Anti-semi-join for NOT IN/NOT EXISTS

Correlated subquery optimization
TiDB attempts to decorrelate correlated subqueries into joins
```sql
SELECT * FROM users u
WHERE u.age > (SELECT AVG(age) FROM users WHERE city = u.city);
```

TiDB may rewrite this as a join internally

TiDB-specific: subquery hints
```sql
SELECT * FROM users WHERE id IN (
    SELECT /*+ SEMI_JOIN_REWRITE() */ user_id FROM orders WHERE amount > 100
);

```

Hash semi-join hint
```sql
SELECT /*+ HASH_JOIN_BUILD(o) */ * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

Comparison operators with subqueries (same as MySQL)
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

```

Limitations:
Correlated subqueries may be slower than in MySQL if not decorrelated
NOT IN with NULL values follows SQL standard (may return empty if subquery has NULLs)
Deeply nested subqueries may have optimization limitations
Some correlated subquery patterns may not be automatically decorrelated
Use EXPLAIN ANALYZE to check if subquery is materialized or executed per-row
