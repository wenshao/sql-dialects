# Hologres: UPDATE

> 参考资料:
> - [Hologres SQL - UPDATE](https://help.aliyun.com/zh/hologres/user-guide/update)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)


注意: Hologres 兼容 PostgreSQL UPDATE 语法
行存表和列存表均支持 UPDATE
基本更新

```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```

## 多列更新

```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```

## 多列用元组赋值

```sql
UPDATE users SET (email, age) = ('new@example.com', 26) WHERE username = 'alice';
```

## FROM 子句（多表更新，PostgreSQL 兼容语法）

```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```

## 子查询更新

```sql
UPDATE users SET age = (SELECT AVG(age)::INTEGER FROM users) WHERE age IS NULL;
```

## RETURNING

```sql
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;
```

## CTE + UPDATE

```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip
WHERE users.id = vip.user_id;
```

## CASE 表达式

```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```

## 自引用更新

```sql
UPDATE users SET age = age + 1;
```

## 从子查询批量更新

```sql
UPDATE users u SET
    email = t.new_email
FROM (VALUES ('alice', 'alice_new@example.com'), ('bob', 'bob_new@example.com'))
    AS t(username, new_email)
WHERE u.username = t.username;
```

性能提示:
按主键更新性能最佳
避免频繁单行更新，建议批量操作
列存表的 UPDATE 涉及行级锁
