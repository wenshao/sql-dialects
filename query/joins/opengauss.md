# openGauss/GaussDB: JOIN

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)


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
支持 FULL OUTER JOIN（比 MySQL 更完整）
GaussDB 分布式版本中同分布键的 JOIN 性能最好
REPLICATION 分布的表与任意表 JOIN 无需跨 DN
支持 LATERAL 子查询
