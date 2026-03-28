# DuckDB: 子查询

> 参考资料:
> - [DuckDB - SQL Reference](https://duckdb.org/docs/sql/introduction)
> - [DuckDB - Functions](https://duckdb.org/docs/sql/functions/overview)
> - [DuckDB - Data Types](https://duckdb.org/docs/sql/data_types/overview)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

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

```

NOT EXISTS
```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

Comparison operators with subquery
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

```

FROM subquery (derived table)
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

LATERAL subquery
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

Row subquery comparison
```sql
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

```

Correlated subquery in SELECT
```sql
SELECT username,
    (SELECT MAX(amount) FROM orders WHERE user_id = users.id) AS max_order
FROM users;

```

Subquery with complex types
```sql
SELECT username,
    (SELECT LIST(amount ORDER BY created_at) FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;

```

Subquery with list/array construction
```sql
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id) AS amounts
FROM users;

```

DuckDB-specific: Subquery with COLUMNS expression
```sql
SELECT (SELECT COUNT(*) FROM users WHERE city = t.city) AS city_count, *
FROM users t;

```

Subquery in HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (SELECT AVG(city_count) FROM (SELECT COUNT(*) AS city_count FROM users GROUP BY city));

```

Nested subqueries
```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

```

Note: DuckDB supports all standard subquery types
Note: LATERAL subqueries are fully supported
Note: Correlated subqueries are automatically decorrelated when possible
Note: LIST() aggregate in subqueries can return array results
Note: Performance: DuckDB's optimizer handles subqueries efficiently
