# Vertica: UPDATE

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


基本更新
```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```


多列更新
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```


表达式更新
```sql
UPDATE users SET age = age + 1;
UPDATE products SET price = price * 1.1;
```


CASE 表达式
```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```


子查询更新
```sql
UPDATE users SET age = (SELECT AVG(age)::INT FROM users) WHERE age IS NULL;
```


FROM 子句
```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```


多表 FROM
```sql
UPDATE users SET status = 2
FROM orders o JOIN vip_list v ON o.user_id = v.user_id
WHERE users.id = o.user_id;
```


CTE + UPDATE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0
WHERE id IN (SELECT id FROM inactive);
```


子查询中的关联更新
```sql
UPDATE users SET
    order_count = (SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id);
```


条件更新
```sql
UPDATE users SET
    email = COALESCE(NULLIF(email, ''), 'unknown@example.com')
WHERE email IS NULL OR email = '';
```


MERGE（更强大的更新方式）
```sql
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    username = s.username,
    email = s.email,
    age = s.age;
```


批量更新（大表推荐 MERGE 或 CTAS）
```sql
MERGE INTO users t
USING (
    SELECT 1 AS id, 'alice_new@example.com' AS email
    UNION ALL
    SELECT 2, 'bob_new@example.com'
) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET email = s.email;
```


注意：Vertica 是列存储，UPDATE 标记旧数据删除，写入新数据
注意：大量 UPDATE 后建议执行 SELECT PURGE_TABLE('users') 清理
注意：大批量更新推荐 MERGE 或 CTAS 替代
注意：支持 FROM 子句（类似 PostgreSQL）
