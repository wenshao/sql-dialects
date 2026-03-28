# Greenplum: 子查询

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


标量子查询
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```


WHERE 子查询
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```


EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```


比较运算符 + 子查询
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```


FROM 子查询（派生表）
```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;
```


关联子查询
```sql
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;
```


LATERAL 子查询（PostgreSQL 9.3+）
```sql
SELECT u.username, latest.*
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders
    WHERE user_id = u.id
    ORDER BY order_date DESC
    LIMIT 3
) latest;
```


行子查询
```sql
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);
```


嵌套子查询
```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);
```


子查询 + 聚合
```sql
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id HAVING SUM(amount) > 10000
);
```


ARRAY 子查询
```sql
SELECT username, ARRAY(SELECT tag FROM user_tags WHERE user_id = users.id) AS tags
FROM users;
```


注意：Greenplum 兼容 PostgreSQL 子查询语法
注意：支持 LATERAL 子查询
注意：关联子查询在分布式环境可能较慢（需要跨 Segment 通信）
注意：优化器会自动将子查询改写为 JOIN
