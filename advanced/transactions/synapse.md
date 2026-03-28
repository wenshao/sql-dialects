# Azure Synapse: 事务

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


基本事务
```sql
BEGIN TRANSACTION;  -- 或 BEGIN TRAN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT TRANSACTION;  -- 或 COMMIT
```


回滚
```sql
BEGIN TRAN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK TRANSACTION;  -- 或 ROLLBACK
```


隐式事务
默认自动提交（每条语句是一个独立事务）
BEGIN TRAN ... COMMIT 定义显式事务边界

隔离级别
Synapse 专用池仅支持 READ UNCOMMITTED
这意味着可以读取未提交的数据（脏读）
```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
```


注意：与 SQL Server 不同，Synapse 不支持：
READ COMMITTED, REPEATABLE READ, SERIALIZABLE, SNAPSHOT

错误处理和事务
```sql
BEGIN TRY
    BEGIN TRAN;

    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;

    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK;

    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR(@msg, 16, 1);
END CATCH;
```


检查事务状态
```sql
SELECT @@TRANCOUNT;                          -- 嵌套事务深度
```


存储过程中的事务
```sql
CREATE PROCEDURE safe_transfer
    @from_id BIGINT,
    @to_id BIGINT,
    @amount DECIMAL(10,2)
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        DECLARE @balance DECIMAL(10,2);
        SELECT @balance = balance FROM accounts WHERE id = @from_id;

        IF @balance < @amount
        BEGIN
            RAISERROR('Insufficient balance', 16, 1);
        END

        UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
        UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;
        THROW;
    END CATCH
END;
```


CTAS 原子性
CTAS 操作本身是原子的（要么全部成功要么全部失败）
```sql
CREATE TABLE new_table
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS SELECT * FROM source_table;
```


分区切换（原子操作）
```sql
ALTER TABLE staging SWITCH PARTITION 1 TO production PARTITION 1;
```


事务限制
Synapse 专用池的事务有以下限制：
1. 最大事务大小限制（取决于 DWU 级别）
2. 长事务可能被系统终止
3. 某些 DDL 操作不能在事务中执行

最佳实践：CTAS 模式（替代大事务）
不推荐：
BEGIN TRAN;
DELETE FROM users WHERE status = 0;  -- 大量删除
COMMIT;

推荐：
```sql
CREATE TABLE users_active
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS SELECT * FROM users WHERE status != 0;
RENAME OBJECT users TO users_old;
RENAME OBJECT users_active TO users;
DROP TABLE users_old;
```


查看活跃事务
```sql
SELECT * FROM sys.dm_pdw_exec_requests
WHERE status = 'Running'
ORDER BY submit_time DESC;
```


注意：Synapse 专用池仅支持 READ UNCOMMITTED 隔离级别
注意：事务有大小限制，大批量操作建议用 CTAS
注意：CTAS 操作本身是原子的
注意：不支持分布式事务
注意：不支持 SAVEPOINT
注意：长事务可能被系统自动终止
注意：Serverless 池不支持 DML 事务
