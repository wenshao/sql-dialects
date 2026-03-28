# Redshift: 子查询

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


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


FROM 子查询
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
    ) WHERE cnt > 100
);
```


子查询 + SUPER 类型
```sql
SELECT id, JSON_EXTRACT_PATH_TEXT(data, 'name') AS name
FROM events
WHERE JSON_EXTRACT_PATH_TEXT(data, 'type') IN (
    SELECT event_type FROM event_config WHERE active = TRUE
);
```


WITH 子句 + 子查询
```sql
WITH top_users AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
    ORDER BY total DESC LIMIT 100
)
SELECT * FROM users WHERE id IN (SELECT user_id FROM top_users);
```


注意：Redshift 不支持 LATERAL 子查询
注意：NOT IN 在有 NULL 时行为不同，推荐用 NOT EXISTS
注意：关联子查询可能比 JOIN 慢，建议用 JOIN 改写
注意：子查询结果不能作为 DISTKEY 优化的依据
