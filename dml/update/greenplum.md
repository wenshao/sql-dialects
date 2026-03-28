# Greenplum: UPDATE

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


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
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```


FROM 子句（PostgreSQL 扩展）
```sql
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;
```


多表 FROM
```sql
UPDATE users u SET status = 2
FROM orders o JOIN vip_list v ON o.user_id = v.user_id
WHERE u.id = o.user_id;
```


CTE + UPDATE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0
WHERE id IN (SELECT id FROM inactive);
```


带 RETURNING
```sql
UPDATE users SET age = age + 1 WHERE username = 'alice'
RETURNING id, username, age;
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


注意：Greenplum 兼容 PostgreSQL UPDATE 语法
注意：UPDATE 会重新分布数据（如果更新了分布键）
注意：大批量 UPDATE 可能性能较低（建议 CTAS 替代）
注意：AO 表的 UPDATE 会标记旧行删除，写入新行
