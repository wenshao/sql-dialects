# YugabyteDB: 子查询

> 参考资料:
> - [YugabyteDB YSQL Reference](https://docs.yugabyte.com/stable/api/ysql/)
> - [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/stable/explore/ysql-language-features/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE subquery
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

```

EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

Comparison operators + subquery
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

```

ANY / ALL / SOME
```sql
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'NYC');
SELECT * FROM users WHERE age > ALL (SELECT age FROM users WHERE city = 'NYC');

```

FROM subquery (derived table)
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

Correlated subquery
```sql
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

```

Lateral subquery (same as PostgreSQL)
```sql
SELECT u.username, latest.amount, latest.order_date
FROM users u
LEFT JOIN LATERAL (
    SELECT amount, order_date FROM orders WHERE user_id = u.id
    ORDER BY order_date DESC LIMIT 3
) latest ON true;

```

Subquery with array
```sql
SELECT * FROM users WHERE 'admin' = ANY(tags);

```

CTE (preferred over deeply nested subqueries)
```sql
WITH high_value_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 1000
)
SELECT u.username, h.total
FROM users u JOIN high_value_orders h ON u.id = h.user_id;

```

Subquery in SELECT with ARRAY constructor
```sql
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id ORDER BY amount DESC) AS order_amounts
FROM users;

```

Subquery in UPDATE
```sql
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000);

```

Subquery in DELETE
```sql
DELETE FROM users
WHERE id NOT IN (SELECT DISTINCT user_id FROM orders);

```

Subquery on partitioned tables
```sql
SELECT * FROM geo_orders
WHERE region = 'us'
AND user_id IN (SELECT id FROM users WHERE status = 1);
```

Partition pruning applied if region is in the WHERE clause

Note: All PostgreSQL subquery types supported
Note: ANY, ALL, SOME operators supported
Note: LATERAL subqueries supported
Note: Correlated subqueries may involve cross-node lookups
Note: Subqueries on co-located tables (tablegroups) are more efficient
Note: CTEs recommended over deeply nested subqueries
