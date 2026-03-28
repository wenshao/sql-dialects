# CockroachDB: JOIN 连接查询

> 参考资料:
> - [CockroachDB - SQL Statements](https://www.cockroachlabs.com/docs/stable/sql-statements)
> - [CockroachDB - Functions and Operators](https://www.cockroachlabs.com/docs/stable/functions-and-operators)
> - [CockroachDB - Data Types](https://www.cockroachlabs.com/docs/stable/data-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

```

LEFT JOIN
```sql
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

```

RIGHT JOIN
```sql
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

```

FULL OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

```

CROSS JOIN
```sql
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

```

Self join
```sql
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

```

USING
```sql
SELECT * FROM users JOIN orders USING (user_id);

```

NATURAL JOIN
```sql
SELECT * FROM users NATURAL JOIN profiles;

```

LATERAL JOIN (same as PostgreSQL)
```sql
SELECT u.username, top_order.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY amount DESC LIMIT 1
) top_order ON true;

```

Multi-table JOIN
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

```

UNNEST (array expansion, same as PostgreSQL)
```sql
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;

```

JOIN with JSONB
```sql
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.metadata @> '{"premium": true}'::JSONB;

```

Lookup join hint (CockroachDB-specific)
```sql
SELECT u.username, o.amount
FROM users u
INNER LOOKUP JOIN orders o ON u.id = o.user_id;
```

Forces index-based lookup join (good for small driving tables)

Merge join hint
```sql
SELECT u.username, o.amount
FROM users u
INNER MERGE JOIN orders o ON u.id = o.user_id;

```

Hash join hint
```sql
SELECT u.username, o.amount
FROM users u
INNER HASH JOIN orders o ON u.id = o.user_id;

```

AS OF SYSTEM TIME join (historical data)
```sql
SELECT u.username, o.amount
FROM users AS OF SYSTEM TIME '-10s' u
JOIN orders AS OF SYSTEM TIME '-10s' o ON u.id = o.user_id;

```

Note: All PostgreSQL JOIN types supported
Note: LOOKUP JOIN, MERGE JOIN, HASH JOIN hints are CockroachDB-specific
Note: AS OF SYSTEM TIME enables follower reads (lower latency)
Note: JOIN performance depends on data locality (co-located tables)
Note: LATERAL JOIN supported (unlike BigQuery)
