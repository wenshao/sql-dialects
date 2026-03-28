# Databricks SQL: UPDATE

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


基本更新（Delta Lake ACID）
```sql
UPDATE users SET age = 26 WHERE username = 'alice';
```


多列更新
```sql
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';
```


子查询更新
```sql
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;
```


多表 JOIN 更新（使用 MERGE 语法实现）
```sql
MERGE INTO users u
USING orders o ON u.id = o.user_id
WHEN MATCHED AND o.amount > 1000 THEN
    UPDATE SET u.status = 1;
```


CTE + UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
WHERE id IN (SELECT user_id FROM vip);
```


CASE 表达式
```sql
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;
```


自引用更新
```sql
UPDATE users SET age = age + 1;
```


条件更新
```sql
UPDATE users SET
    email = CASE WHEN email IS NULL THEN 'unknown@example.com' ELSE email END,
    updated_at = current_timestamp()
WHERE status = 1;
```


基于子查询的批量更新
```sql
MERGE INTO users u
USING (
    SELECT 'alice' AS username, 'alice_new@example.com' AS new_email
    UNION ALL
    SELECT 'bob', 'bob_new@example.com'
) t ON u.username = t.username
WHEN MATCHED THEN
    UPDATE SET u.email = t.new_email;
```


UPDATE 后查看变更历史（Time Travel）
```sql
DESCRIBE HISTORY users;
```


查看变更前的数据
```sql
SELECT * FROM users VERSION AS OF 5;
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00';
```


变更数据捕获（Change Data Feed）
需要先启用：ALTER TABLE users SET TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true')
```sql
SELECT * FROM table_changes('users', 5, 10);
SELECT * FROM table_changes('users', '2024-01-15', '2024-01-16');
```


删除向量（Deletion Vectors，提升 UPDATE/DELETE 性能）
启用后，UPDATE 只写标记文件，不立即重写数据文件
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.enableDeletionVectors' = 'true');
```


注意：Delta Lake 的 UPDATE 是 ACID 操作
注意：UPDATE 底层通过 copy-on-write 或 deletion vectors 实现
注意：Time Travel 允许查看和恢复更新前的数据
注意：不支持 UPDATE ... FROM 语法（用 MERGE 代替多表更新）
注意：Deletion Vectors 显著提升 UPDATE 性能（避免整文件重写）
注意：Change Data Feed 可以追踪所有变更记录
