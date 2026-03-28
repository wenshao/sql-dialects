# Azure Synapse: DELETE

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


基本删除
```sql
DELETE FROM users WHERE username = 'alice';
```


子查询删除
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```


JOIN 删除（T-SQL 风格）
```sql
DELETE u
FROM users u
INNER JOIN blacklist b ON u.email = b.email;
```


多表 JOIN 删除
```sql
DELETE u
FROM users u
INNER JOIN blacklist b ON u.email = b.email
INNER JOIN suspension s ON u.id = s.user_id;
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


TRUNCATE（更快）
```sql
TRUNCATE TABLE users;
```


CASE 条件删除
```sql
DELETE FROM users
WHERE CASE
    WHEN status = 0 AND last_login < '2023-01-01' THEN 1
    WHEN status = -1 THEN 1
    ELSE 0
END = 1;
```


CTAS 模式删除（大批量删除推荐）
保留需要的行，比 DELETE 更高效
```sql
CREATE TABLE users_clean
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT * FROM users WHERE status >= 0 AND last_login >= '2023-01-01';

RENAME OBJECT users TO users_old;
RENAME OBJECT users_clean TO users;
DROP TABLE users_old;
```


注意：大批量 DELETE 建议用 CTAS 模式（保留需要的行）
注意：DELETE 在列存储上创建 delete bitmap，影响查询性能
注意：频繁 DELETE 后需要 ALTER INDEX ALL ON table REBUILD
注意：TRUNCATE 比 DELETE 快，重置表空间
注意：不支持 DELETE ... OUTPUT（SQL Server 的功能）
注意：Serverless 池不支持 DELETE（只读外部数据）
