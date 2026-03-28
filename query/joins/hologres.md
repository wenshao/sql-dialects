# Hologres: JOIN（兼容 PostgreSQL 语法）

> 参考资料:
> - [Hologres SQL - SELECT (JOIN)](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - INNER JOIN

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

## UNNEST：展开数组列（兼容 PostgreSQL 语法）

```sql
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS tag;
```

## 多表 JOIN

```sql
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```

## 本地表与外部表 JOIN

Hologres 支持内部表与 MaxCompute 外部表的联邦查询

```sql
SELECT h.username, m.order_amount
FROM hologres_users h
JOIN maxcompute_orders m ON h.id = m.user_id;
```

JOIN 性能优化：分布键对齐
建议：JOIN 列与表的分布键（distribution_key）一致，可避免数据 shuffle
CREATE TABLE users (id INT, username TEXT) WITH (distribution_key = 'id');
CREATE TABLE orders (id INT, user_id INT) WITH (distribution_key = 'user_id');
注意：Hologres 兼容 PostgreSQL 语法，大部分 PostgreSQL JOIN 语法均可使用
注意：Hologres 不支持 LATERAL JOIN
注意：Hologres 行存表和列存表的 JOIN 性能特性不同
