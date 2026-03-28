# Hologres: 子查询（兼容 PostgreSQL 语法）

> 参考资料:
> - [Hologres SQL - SELECT](https://help.aliyun.com/zh/hologres/user-guide/select)
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)


## 标量子查询

```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
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
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
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

## 行子查询

```sql
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);
```

## 数组子查询（兼容 PostgreSQL）

```sql
SELECT * FROM users WHERE id = ANY(ARRAY(SELECT user_id FROM orders WHERE amount > 100));
```

## 嵌套子查询

```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);
```

## 子查询 + 联邦查询（内部表 + MaxCompute 外部表）

```sql
SELECT * FROM hologres_users
WHERE id IN (SELECT user_id FROM maxcompute_orders WHERE amount > 100);
```

注意：Hologres 兼容 PostgreSQL 语法，大部分 PostgreSQL 子查询语法均可使用
注意：Hologres 不支持 LATERAL 子查询
注意：关联子查询在大数据量场景下建议改写为 JOIN 以获取更好性能
