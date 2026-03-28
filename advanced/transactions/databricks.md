# Databricks SQL: 事务

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


Delta Lake 提供 ACID 事务支持
每个 DML 操作（INSERT/UPDATE/DELETE/MERGE）都是一个原子事务
不需要显式 BEGIN / COMMIT / ROLLBACK

## 自动 ACID 事务（Delta Lake 核心特性）


每个 DML 操作自动具有 ACID 属性
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
-- 写入是原子的：要么完全成功，要么完全回滚

UPDATE users SET age = 26 WHERE username = 'alice';
-- 更新是原子的：并发读取看到一致的快照

DELETE FROM users WHERE status = 0;
-- 删除是原子的

MERGE INTO users AS t
USING staging AS s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;
-- MERGE 是原子的
```


## 乐观并发控制（OCC）


Delta Lake 使用乐观并发控制
多个写入者可以同时写入，冲突时最后提交者失败
自动重试机制可以处理大部分冲突

隔离级别：
WriteSerializable（默认）：写操作串行化，读操作快照隔离
Serializable：完全串行化

设置隔离级别
```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.isolationLevel' = 'Serializable');
ALTER TABLE users SET TBLPROPERTIES ('delta.isolationLevel' = 'WriteSerializable');
```


## Time Travel（事务历史）


每个事务创建一个新版本
```sql
DESCRIBE HISTORY users;
-- 返回：版本号、时间戳、操作类型、操作参数等
```


读取特定版本（事务快照）
```sql
SELECT * FROM users VERSION AS OF 5;
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00';
```


回滚到之前版本（相当于 ROLLBACK 到某个点）
```sql
RESTORE TABLE users TO VERSION AS OF 5;
RESTORE TABLE users TO TIMESTAMP AS OF '2024-01-15 10:00:00';
```


## 多语句事务替代方案


Delta Lake 不支持显式 BEGIN / COMMIT 跨多条语句
使用以下替代方案：

方案一：MERGE 实现多步操作的原子性
```sql
MERGE INTO accounts AS t
USING (
    SELECT 1 AS id, -100 AS delta
    UNION ALL
    SELECT 2 AS id, 100 AS delta
) AS s ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET balance = t.balance + s.delta;
-- 一条 MERGE 语句实现转账的原子性
```


方案二：使用临时视图 + CTAS
```sql
CREATE OR REPLACE TABLE accounts_updated AS
WITH transfers AS (
    SELECT id,
        CASE id
            WHEN 1 THEN balance - 100
            WHEN 2 THEN balance + 100
            ELSE balance
        END AS balance
    FROM accounts
)
SELECT * FROM transfers;
-- CTAS 操作是原子的
```


## Change Data Feed（事务审计）


```sql
ALTER TABLE users SET TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');
```


查看特定版本范围的变更
```sql
SELECT * FROM table_changes('users', 5, 10);
```


按时间查看变更
```sql
SELECT * FROM table_changes('users', '2024-01-15', '2024-01-16');
```


## 并发控制


Delta Lake 自动处理并发：
1. 并发读取：始终成功（快照隔离）
2. 并发写入不同分区：自动成功
3. 并发写入相同数据：冲突检测，失败者可重试

启用行级并发（减少冲突）
```sql
ALTER TABLE users SET TBLPROPERTIES (
    'delta.enableDeletionVectors' = 'true',
    'delta.enableRowTracking' = 'true'
);
```


## VACUUM 和日志保留


清理旧版本文件
```sql
VACUUM users RETAIN 168 HOURS;
```


日志保留
```sql
ALTER TABLE users SET TBLPROPERTIES (
    'delta.logRetentionDuration' = 'interval 30 days',
    'delta.deletedFileRetentionDuration' = 'interval 7 days'
);
```


注意：Delta Lake 每个 DML 操作自动是 ACID 事务
注意：不支持显式 BEGIN / COMMIT / ROLLBACK 跨多条语句
注意：使用 MERGE 实现多步操作的原子性
注意：Time Travel 提供事务历史和回滚能力
注意：RESTORE TABLE 可以回滚到任意历史版本
注意：乐观并发控制自动处理大部分冲突
注意：Deletion Vectors + Row Tracking 减少写入冲突
