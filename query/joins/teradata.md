# Teradata: JOIN

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


INNER JOIN
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


Multi-table join
```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id;
```


Product join (Teradata-specific syntax, equivalent to CROSS JOIN)
```sql
SELECT u.username, r.role_name
FROM users u, roles r;
```


Hash join hint (Teradata optimizer usually chooses, but can hint)
Note: Teradata automatically selects join strategy based on PI alignment

Nested join hint
```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE u.city = 'Beijing';
```


NORMALIZE (Teradata-specific: merge overlapping periods)
```sql
SELECT emp_id, BEGIN(combined) AS start_date, END(combined) AS end_date
FROM (
    SELECT emp_id, NORMALIZE period_col AS combined
    FROM employee_periods
) t;
```


Note: joins perform best when PRIMARY INDEX columns align
Note: PI-to-PI joins avoid redistribution (merge join)
Note: when PIs differ, Teradata redistributes or duplicates data
Note: EXPLAIN shows join strategies (merge, hash, nested, product)
