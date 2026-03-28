# Apache Impala: 子查询

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Impala Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


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
```


FROM 子查询（派生表，必须有别名）
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


嵌套子查询
```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);
```


SEMI JOIN（等价于 IN / EXISTS）
```sql
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;
```


ANTI JOIN（等价于 NOT IN / NOT EXISTS）
```sql
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;
```


RIGHT SEMI JOIN
```sql
SELECT o.*
FROM users u
RIGHT SEMI JOIN orders o ON u.id = o.user_id;
```


RIGHT ANTI JOIN
```sql
SELECT o.*
FROM users u
RIGHT ANTI JOIN orders o ON u.id = o.user_id;
```


子查询 + 聚合
```sql
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id HAVING SUM(amount) > 10000
);
```


行子查询（不支持）
SELECT * FROM users WHERE (city, age) IN (...);  -- 不支持

注意：Impala 支持标准子查询语法
注意：支持 LEFT/RIGHT SEMI JOIN 和 ANTI JOIN
注意：不支持 LATERAL 子查询
注意：不支持行子查询（多列 IN 子查询）
注意：不支持 ALL/ANY/SOME 运算符
注意：优化器自动将 IN/EXISTS 改写为 SEMI JOIN
