# Flink SQL: 子查询

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE subquery with IN
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

FROM subquery (derived table)
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

Correlated subquery in SELECT
```sql
SELECT username,
    (SELECT MAX(amount) FROM orders WHERE user_id = users.id) AS max_order
FROM users;

```

Correlated subquery in WHERE
```sql
SELECT * FROM users u
WHERE (SELECT SUM(amount) FROM orders WHERE user_id = u.id) > 1000;

```

Subquery in HAVING
```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

```

Subquery as table in JOIN
```sql
SELECT u.username, o.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders
    GROUP BY user_id
) o ON u.id = o.user_id;

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

Semi-join via IN subquery (optimized by Flink)
Flink rewrites IN subqueries to semi-joins when possible
```sql
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 1000);

```

Anti-join via NOT IN subquery (optimized by Flink)
```sql
SELECT * FROM users
WHERE id NOT IN (SELECT user_id FROM blacklist WHERE active = true);

```

Subquery in streaming context: deduplication
```sql
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time DESC) AS rn
    FROM events
) WHERE rn = 1;

```

Subquery for Top-N per group
```sql
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY sales DESC) AS rn
    FROM products
) WHERE rn <= 3;

```

Note: Flink supports scalar, IN, EXISTS, and correlated subqueries
Note: No LATERAL subqueries
Note: ALL/ANY/SOME subquery operators are supported
Note: Correlated subqueries in streaming mode require careful state management
Note: IN/EXISTS subqueries are optimized into semi-joins by the optimizer
Note: Subqueries in FROM clause are common for deduplication and Top-N patterns
Note: Complex nested correlated subqueries may not be supported in streaming mode
