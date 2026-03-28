# Databricks SQL: DELETE

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


基本删除（Delta Lake ACID）
```sql
DELETE FROM users WHERE username = 'alice';
```


子查询删除
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
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


条件删除
```sql
DELETE FROM users
WHERE status = 0 AND last_login < '2023-01-01';

DELETE FROM users
WHERE CASE
    WHEN status = 0 AND last_login < '2023-01-01' THEN true
    WHEN status = -1 THEN true
    ELSE false
END;
```


使用 MERGE 进行多表关联删除
```sql
MERGE INTO users u
USING blacklist b ON u.email = b.email
WHEN MATCHED THEN DELETE;
```


删除所有行
```sql
DELETE FROM users;
```


TRUNCATE
```sql
TRUNCATE TABLE users;
```


删除后查看变更历史（Time Travel）
```sql
DESCRIBE HISTORY users;
```


恢复已删除的数据（Time Travel）
查看删除前的数据
```sql
SELECT * FROM users VERSION AS OF 5;
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00';
```


恢复整个表到之前版本
```sql
RESTORE TABLE users TO VERSION AS OF 5;
RESTORE TABLE users TO TIMESTAMP AS OF '2024-01-15 10:00:00';
```


变更数据捕获（Change Data Feed）
```sql
SELECT * FROM table_changes('users', 5) WHERE _change_type = 'delete';
```


删除向量（Deletion Vectors）
启用后 DELETE 只写标记，不重写数据文件
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.enableDeletionVectors' = 'true');
```


清理已删除数据的物理文件
```sql
VACUUM users;
VACUUM users RETAIN 168 HOURS;
```


注意：DELETE 是 ACID 操作，对其他并发读取无影响
注意：Time Travel 允许查看和恢复删除前的数据
注意：VACUUM 后早于保留期的时间旅行将不可用
注意：Deletion Vectors 显著提升 DELETE 性能
注意：RESTORE TABLE 可以回滚到任意历史版本
注意：不支持 DELETE ... USING / FROM 语法（用 MERGE 代替）
