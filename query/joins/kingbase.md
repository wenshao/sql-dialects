# KingbaseES (人大金仓): JOIN

PostgreSQL compatible syntax.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)


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

## 自连接

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

## LATERAL（子查询可以引用外部表的列）

```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;
```

## LEFT JOIN LATERAL

```sql
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;
```

注意事项：
语法与 PostgreSQL 完全兼容
支持 FULL OUTER JOIN
支持 LATERAL 子查询
