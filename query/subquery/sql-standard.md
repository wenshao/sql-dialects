# SQL 标准: 子查询

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - Subqueries](https://modern-sql.com/feature/subquery)

## SQL-86 (SQL1)

基本子查询支持

标量子查询
```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;
```

WHERE IN 子查询
```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
```

比较运算符 + 子查询
```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
```

## SQL-92 (SQL2)

增强子查询支持

EXISTS
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

ALL / ANY / SOME
```sql
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');
```

SOME 等价于 ANY
```sql
SELECT * FROM users WHERE age > SOME (SELECT age FROM users WHERE city = 'Beijing');
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

行子查询
```sql
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);
```

## SQL:1999 (SQL3)

引入 WITH 子句（CTE）作为子查询替代方案
LATERAL 概念引入

## SQL:2003

LATERAL 子查询（正式标准化）
```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;
```

数组子查询（ARRAY 值构造器）
```sql
SELECT username,
    ARRAY(SELECT amount FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;
```

MULTISET 子查询
```sql
SELECT username,
    MULTISET(SELECT amount FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;
```

## SQL:2016

JSON 相关子查询
```sql
SELECT * FROM users
WHERE id IN (
    SELECT CAST(JSON_VALUE(data, '$.user_id') AS INT) FROM events
);
```

各标准版本子查询特性总结：
SQL-86: 基本标量子查询、WHERE IN
SQL-92: EXISTS, ALL/ANY/SOME, FROM 子查询, 关联子查询, 行子查询
SQL:1999: WITH（CTE）引入
SQL:2003: LATERAL 子查询, ARRAY/MULTISET 子查询
SQL:2016: JSON 相关子查询支持
