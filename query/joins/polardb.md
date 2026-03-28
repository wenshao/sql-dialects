# PolarDB: JOIN

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


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

## 多表 JOIN

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```

## USING

```sql
SELECT * FROM users JOIN orders USING (user_id);
```

## NATURAL JOIN

```sql
SELECT * FROM users NATURAL JOIN orders;
```

## LATERAL

```sql
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest ON TRUE;
```

## 模拟 FULL OUTER JOIN（MySQL 不原生支持）

```sql
SELECT * FROM users u LEFT JOIN orders o ON u.id = o.user_id
UNION
SELECT * FROM users u RIGHT JOIN orders o ON u.id = o.user_id;
```

注意事项：
同分区键的表 JOIN 性能最好（co-located join，不跨分片）
不同分区键的表 JOIN 需要数据重分布（跨节点传输）
广播表与任意表 JOIN 无需跨分片
LATERAL 子查询在分布式环境下可能性能较差
