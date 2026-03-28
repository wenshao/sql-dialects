# IBM Db2: JOIN

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


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

## LATERAL (Db2 9.1+, subquery can reference outer table)

```sql
SELECT u.username, latest.amount
FROM users u,
LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) AS latest;
```

## LEFT JOIN LATERAL

```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
    FETCH FIRST 1 ROW ONLY
) AS latest ON 1=1;
```

## EXCEPTION JOIN (Db2-specific: return non-matching rows)

```sql
SELECT u.* FROM users u
EXCEPTION JOIN blacklist b ON u.email = b.email;
```

## Multi-table join

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;
```

## Join with XMLTABLE (join relational with XML data)

```sql
SELECT u.username, x.phone
FROM users u,
XMLTABLE('$d/phones/phone' PASSING u.contact_xml AS "d"
    COLUMNS phone VARCHAR(20) PATH '.') AS x;
```

## Note: Db2 optimizer chooses join method (nested loop, merge, hash)

Note: RUNSTATS helps optimizer choose best join strategy
