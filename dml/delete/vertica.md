# Vertica: DELETE

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


基本删除
```sql
DELETE FROM users WHERE username = 'alice';
```


条件删除
```sql
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';
```


子查询删除
```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```


EXISTS 子查询
```sql
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);
```


NOT EXISTS
```sql
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```


CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```


范围删除
```sql
DELETE FROM orders WHERE order_date < '2023-01-01';
```


删除所有行
```sql
DELETE FROM users;
```


TRUNCATE（高效全表删除）
```sql
TRUNCATE TABLE users;
```


删除分区（通过 SELECT PARTITION_TABLE 管理）
```sql
SELECT DROP_PARTITIONS('orders', '2023-01-01', '2023-12-31');
```


清除删除标记（DELETE 后数据标记为已删除但不立即移除）
```sql
SELECT PURGE_TABLE('users');
SELECT PURGE_PARTITION('orders', '2024-01-01');
```


合并 ROS 容器（优化存储）
```sql
SELECT DO_TM_TASK('mergeout', 'users');
```


MERGE 方式删除（更灵活）
```sql
MERGE INTO users t
USING blacklist s ON t.email = s.email
WHEN MATCHED THEN DELETE;
```


批量条件删除
```sql
DELETE FROM events
WHERE event_time < TIMESTAMPADD(MONTH, -6, CURRENT_TIMESTAMP);
```


注意：Vertica DELETE 标记数据为已删除，不立即移除
注意：定期执行 PURGE_TABLE 或 PURGE_PARTITION 清理
注意：Tuple Mover 后台自动执行 mergeout 操作
注意：TRUNCATE 比 DELETE 快（立即释放空间）
注意：DROP_PARTITIONS 是删除大量时间范围数据的最高效方式
