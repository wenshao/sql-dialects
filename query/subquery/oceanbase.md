# OceanBase: 子查询

> 参考资料:
> - [OceanBase SQL Reference (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase SQL Reference (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## MySQL Mode (same as MySQL with optimizer differences)


Scalar subquery
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE IN subquery
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

```

EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

FROM subquery (derived table)
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

LATERAL derived table (4.0+)
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

Comparison operators
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');

```

## Oracle Mode


Scalar subquery (same syntax)
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE IN subquery
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

```

EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

FROM subquery (no alias required in Oracle mode)
```sql
SELECT * FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) WHERE cnt > 10;

```

ROWNUM (Oracle-specific, used in subqueries for limiting)
```sql
SELECT * FROM (
    SELECT u.*, ROWNUM AS rn FROM users u WHERE ROWNUM <= 20
) WHERE rn > 10;

```

Correlated subquery (Oracle mode)
```sql
SELECT * FROM users u
WHERE u.age > (SELECT AVG(age) FROM users WHERE city = u.city);

```

WITH clause as subquery (Oracle CTE style)
```sql
SELECT * FROM (
    WITH active AS (SELECT * FROM users WHERE status = 1)
    SELECT * FROM active WHERE age > 25
);

```

Multiset subqueries (Oracle mode, 4.0+)
Limited support for MULTISET operators

Optimizer hints for subqueries
```sql
SELECT /*+ UNNEST */ * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

SELECT /*+ NO_UNNEST */ * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

```

Limitations:
MySQL mode: mostly identical to MySQL subquery behavior
Oracle mode: ROWNUM available, no alias required for inline views
Subquery flattening/unnesting controlled by optimizer
Complex correlated subqueries may not always be decorrelated
