-- SQL Server: 事务
--
-- 参考资料:
--   [1] SQL Server T-SQL - BEGIN TRANSACTION
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/begin-transaction-transact-sql
--   [2] SQL Server T-SQL - SET TRANSACTION ISOLATION LEVEL
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql
--   [3] SQL Server T-SQL - TRY...CATCH
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql

-- 基本事务
BEGIN TRANSACTION;  -- 或 BEGIN TRAN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT TRANSACTION;  -- 或 COMMIT

-- 回滚
BEGIN TRAN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK TRANSACTION;

-- 保存点
BEGIN TRAN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVE TRANSACTION sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TRANSACTION sp1;  -- 回滚到保存点
COMMIT;

-- 自动提交：默认每条语句自动提交
SET IMPLICIT_TRANSACTIONS ON;  -- 关闭自动提交

-- 隔离级别
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;             -- 2005+，类似 Oracle 的 MVCC

-- 查看当前隔离级别
DBCC USEROPTIONS;

-- 快照隔离（需要先在数据库级别启用）
ALTER DATABASE mydb SET ALLOW_SNAPSHOT_ISOLATION ON;
-- READ COMMITTED SNAPSHOT（推荐，无需显式设置事务级别）
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;

-- 锁相关（锁提示）
SELECT * FROM accounts WITH (UPDLOCK) WHERE id = 1;          -- 更新锁
SELECT * FROM accounts WITH (XLOCK) WHERE id = 1;            -- 排他锁
SELECT * FROM accounts WITH (HOLDLOCK) WHERE id = 1;         -- 保持到事务结束
SELECT * FROM accounts WITH (NOLOCK) WHERE id = 1;           -- 脏读（不推荐）
SELECT * FROM accounts WITH (ROWLOCK) WHERE id = 1;          -- 强制行锁
SELECT * FROM accounts WITH (TABLOCK) WHERE id = 1;          -- 表锁
SELECT * FROM accounts WITH (UPDLOCK, ROWLOCK) WHERE id = 1; -- 组合

-- 错误处理
BEGIN TRY
    BEGIN TRAN;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
    THROW;  -- 2012+，重新抛出异常
END CATCH;

-- 2014+: 内存优化表的事务
-- BEGIN TRAN ... COMMIT（使用乐观并发控制）

-- 注意：DDL 是事务性的（可以回滚）
-- 注意：默认使用悲观并发（锁），开启 SNAPSHOT 后使用乐观并发
