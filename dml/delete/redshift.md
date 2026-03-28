# Redshift: DELETE

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


基本删除
```sql
DELETE FROM users WHERE username = 'alice';
```


子查询删除
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```


USING 子句（多表删除，PostgreSQL 风格）
```sql
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;
```


多表 USING
```sql
DELETE FROM users
USING blacklist b, suspension s
WHERE users.email = b.email OR users.id = s.user_id;
```


EXISTS 子查询
```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = users.email);
```


CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```


删除所有行
```sql
DELETE FROM users;
```


TRUNCATE（更快，重置表空间）
```sql
TRUNCATE TABLE users;
```


CASE 条件删除
```sql
DELETE FROM users
WHERE CASE
    WHEN status = 0 AND last_login < '2023-01-01' THEN TRUE
    WHEN status = -1 THEN TRUE
    ELSE FALSE
END;
```


注意：DELETE 在 Redshift 中标记行为已删除（ghost rows），不立即回收空间
注意：需要定期运行 VACUUM DELETE 回收空间
```sql
VACUUM DELETE ONLY users;
```


注意：TRUNCATE 比 DELETE 快得多（重置表，不留 ghost rows）
注意：大批量删除建议用 CTAS 保留需要的行：
CREATE TABLE users_new AS SELECT * FROM users WHERE status != -1;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

注意：DELETE 不支持 LIMIT
注意：DELETE 不支持 RETURNING
注意：DELETE 不支持别名（不能 DELETE FROM users u）
注意：TRUNCATE 会重置 IDENTITY 计数器
