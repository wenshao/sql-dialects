# Materialize: 子查询

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


## Materialize 支持丰富的子查询（兼容 PostgreSQL）

标量子查询

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

## WHERE 子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

## EXISTS

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

## 比较运算符 + 子查询

```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
```

## FROM 子查询

```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```

## 关联子查询

```sql
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;
```

## ANY / ALL

```sql
SELECT * FROM users
WHERE age > ALL (SELECT age FROM users WHERE city = 'New York');
```

## 物化视图中的子查询


## 子查询在物化视图中会被增量维护

```sql
CREATE MATERIALIZED VIEW users_with_orders AS
SELECT u.*, (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count
FROM users u;
```

## EXISTS 在物化视图中

```sql
CREATE MATERIALIZED VIEW active_users AS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id
    AND o.order_date > NOW() - INTERVAL '30 days');
```

## LATERAL 子查询


```sql
SELECT u.username, latest.amount, latest.order_date
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders o
    WHERE o.user_id = u.id
    ORDER BY order_date DESC
    LIMIT 1
) latest;
```

注意：Materialize 支持完整的 PostgreSQL 子查询
注意：子查询在物化视图中会被增量维护
注意：关联子查询可能影响物化视图的内存消耗
注意：LATERAL 子查询也受支持
