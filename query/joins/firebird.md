# Firebird: JOIN

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


## INNER JOIN

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;
```

## LEFT JOIN

```sql
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;
```

## RIGHT JOIN

```sql
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;
```

## FULL OUTER JOIN

```sql
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;
```

## CROSS JOIN

```sql
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;
```

## Self join

```sql
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;
```

## USING

```sql
SELECT * FROM users JOIN orders USING (user_id);
```

## NATURAL JOIN

```sql
SELECT * FROM users NATURAL JOIN orders;
```

## Multi-table join

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;
```

## Join with PLAN clause (control join strategy)

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
PLAN JOIN (users NATURAL, orders INDEX (idx_user_id));
```

## PLAN with specific join method

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
PLAN MERGE (SORT (users NATURAL), SORT (orders NATURAL));
```

## PLAN HASH JOIN (3.0+)

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
PLAN HASH (users NATURAL, orders NATURAL);
```

## Selectable stored procedure as join source (Firebird unique)

```sql
SELECT u.username, sp.total
FROM users u
JOIN get_user_totals(u.id) sp ON 1=1;
```

Note: Firebird supports PLAN clause to manually control query execution
Note: join types: MERGE, SORT MERGE, HASH (3.0+), NESTED LOOP
Note: Firebird's optimizer has improved significantly in 3.0+
Note: no LATERAL joins; use correlated subqueries or selectable procedures
