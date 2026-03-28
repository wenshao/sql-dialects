# Materialize: JOIN

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


Materialize 支持丰富的 JOIN 语法（兼容 PostgreSQL）
在物化视图中 JOIN 会增量维护
INNER JOIN

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

## 多表 JOIN

```sql
SELECT u.username, o.amount, p.name AS product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;
```

## LATERAL JOIN

```sql
SELECT u.username, latest.*
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders o
    WHERE o.user_id = u.id
    ORDER BY order_date DESC
    LIMIT 3
) latest;
```

## 物化视图中的 JOIN（增量维护）


## 多源 JOIN 的物化视图

```sql
CREATE MATERIALIZED VIEW enriched_orders AS
SELECT o.id AS order_id, o.amount,
       u.username, u.email,
       p.name AS product_name
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN products p ON o.product_id = p.id;
```

## 任何一个源表的变更都会触发增量更新

## 跨 SOURCE 的 JOIN


## Kafka SOURCE 与 PostgreSQL SOURCE 的 JOIN

```sql
CREATE MATERIALIZED VIEW realtime_dashboard AS
SELECT k.event_type, k.event_time,
       u.username, u.email
FROM kafka_events k
JOIN pg_users u ON k.user_id = u.id;
```

注意：Materialize 支持完整的 SQL JOIN
注意：物化视图中的 JOIN 会增量维护
注意：跨 SOURCE 的 JOIN 是 Materialize 的核心能力
注意：JOIN 性能取决于数据规模和维护状态的内存消耗
