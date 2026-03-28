# Derby: 子查询

> 参考资料:
> - [Derby SQL Reference](https://db.apache.org/derby/docs/10.16/ref/)
> - [Derby Developer Guide](https://db.apache.org/derby/docs/10.16/devguide/)
> - 标量子查询

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

## FROM 子查询（表表达式）

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
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'New York');
SELECT * FROM users WHERE age > ALL (SELECT age FROM users WHERE city = 'New York');
```

## IN + 多列（不直接支持，使用 EXISTS 替代）

```sql
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM (
        SELECT city, MAX(age) AS max_age FROM users GROUP BY city
    ) t WHERE t.city = u.city AND t.max_age = u.age
);
```

## 嵌套子查询

```sql
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders
    WHERE amount > (SELECT AVG(amount) FROM orders)
);
```

注意：Derby 支持标准的子查询功能
注意：不支持多列 IN 子查询
注意：不支持 LATERAL 子查询
注意：老版本不支持 CTE，建议使用子查询替代
注意：关联子查询性能可能较差
