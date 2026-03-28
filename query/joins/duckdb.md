# DuckDB: JOIN 连接查询

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

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
SELECT * FROM users NATURAL JOIN orders;

```

LATERAL join (subquery can reference outer table)
```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

```

LEFT JOIN LATERAL
```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;

```

POSITIONAL JOIN (DuckDB-specific: join by position, not condition)
```sql
SELECT * FROM range(5) POSITIONAL JOIN (SELECT unnest(['a','b','c','d','e']));

```

ASOF JOIN (DuckDB v0.8+, time-series join to nearest match)
```sql
SELECT s.ticker, s.when, s.price, t.when AS trade_time, t.volume
FROM stock_prices s
ASOF JOIN trades t
ON s.ticker = t.ticker AND s.when >= t.when;

```

ASOF LEFT JOIN
```sql
SELECT s.*, t.volume
FROM stock_prices s
ASOF LEFT JOIN trades t
ON s.ticker = t.ticker AND s.when >= t.when;

```

SEMI JOIN (return left rows that have a match)
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

Or with SEMI JOIN syntax:
```sql
SELECT * FROM users SEMI JOIN orders ON users.id = orders.user_id;

```

ANTI JOIN (return left rows that have no match)
```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

Or with ANTI JOIN syntax:
```sql
SELECT * FROM users ANTI JOIN orders ON users.id = orders.user_id;

```

Join with USING and SELECT * EXCLUDE
```sql
SELECT * EXCLUDE (user_id) FROM users JOIN orders USING (user_id);

```

Multiple joins
```sql
SELECT u.username, o.amount, p.name AS product
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN products p ON o.product_id = p.id;

```

Join with complex types (list contains)
```sql
SELECT u.username, t.tag
FROM users u, UNNEST(u.tags) AS t(tag)
WHERE t.tag LIKE 'vip%';

```

Note: DuckDB supports all standard join types plus ASOF, POSITIONAL, SEMI, ANTI
Note: ASOF JOIN is unique to DuckDB, excellent for time-series data
Note: POSITIONAL JOIN is unique, joins by row position
Note: Hash joins are the default; DuckDB auto-selects the best join strategy
