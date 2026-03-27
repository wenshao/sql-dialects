-- SQL Server: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Microsoft Docs - Transaction Locking and Row Versioning Guide
--       https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide
--   [2] Microsoft Docs - Table Hints
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/hints-transact-sql-table
--   [3] Microsoft Docs - sys.dm_tran_locks
--       https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-tran-locks-transact-sql
--   [4] Microsoft Docs - sp_getapplock
--       https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-getapplock-transact-sql

-- ============================================================
-- 锁提示 (Lock Hints) — SQL Server 特有
-- ============================================================

-- NOLOCK (= READUNCOMMITTED): 不获取共享锁，允许脏读
SELECT * FROM orders WITH (NOLOCK) WHERE status = 'pending';

-- HOLDLOCK (= SERIALIZABLE): 持有共享锁直到事务结束
SELECT * FROM orders WITH (HOLDLOCK) WHERE id = 100;

-- UPDLOCK: 获取更新锁，防止死锁
SELECT * FROM orders WITH (UPDLOCK) WHERE id = 100;

-- XLOCK: 获取排他锁
SELECT * FROM orders WITH (XLOCK) WHERE id = 100;

-- ROWLOCK: 强制使用行锁（而非页锁或表锁）
SELECT * FROM orders WITH (ROWLOCK, UPDLOCK) WHERE id = 100;

-- PAGLOCK: 强制使用页锁
SELECT * FROM orders WITH (PAGLOCK) WHERE status = 'pending';

-- TABLOCK: 强制使用表级共享锁
SELECT * FROM orders WITH (TABLOCK);

-- TABLOCKX: 强制使用表级排他锁
SELECT * FROM orders WITH (TABLOCKX);

-- READPAST: 跳过被锁定的行（类似 SKIP LOCKED）
SELECT TOP 5 * FROM tasks WITH (READPAST, UPDLOCK)
WHERE status = 'pending'
ORDER BY created_at;

-- NOWAIT: 无法获取锁时立即报错
SELECT * FROM orders WITH (NOWAIT) WHERE id = 100;

-- 组合使用
SELECT * FROM orders WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE id = 100;

-- ============================================================
-- 行级锁 — 通过事务实现
-- ============================================================

BEGIN TRANSACTION;
    -- 使用 UPDLOCK 获取更新锁（类似 SELECT FOR UPDATE）
    SELECT * FROM accounts WITH (UPDLOCK, ROWLOCK)
    WHERE id = 1;

    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 表级锁
-- ============================================================

-- SQL Server 没有 LOCK TABLE 语句，使用表提示代替
BEGIN TRANSACTION;
    SELECT * FROM orders WITH (TABLOCKX, HOLDLOCK);
    -- 此时 orders 表被排他锁定
COMMIT;

-- sp_tableoption 禁止锁升级
EXEC sp_tableoption 'orders', 'lock escalation', 'DISABLE';

-- ALTER TABLE 控制锁升级行为（SQL Server 2008+）
ALTER TABLE orders SET (LOCK_ESCALATION = TABLE);     -- 默认
ALTER TABLE orders SET (LOCK_ESCALATION = DISABLE);   -- 禁用
ALTER TABLE orders SET (LOCK_ESCALATION = AUTO);      -- 分区表逐分区升级

-- ============================================================
-- 乐观锁 (Optimistic Locking)
-- ============================================================

-- 使用 rowversion/timestamp 列（SQL Server 自动更新）
ALTER TABLE orders ADD row_ver ROWVERSION;

-- rowversion 在每次更新时自动递增
UPDATE orders
SET status = 'shipped'
WHERE id = 100 AND row_ver = 0x00000000000007D1;
-- 检查 @@ROWCOUNT 是否为 1

-- 使用自定义版本号
ALTER TABLE orders ADD version INT NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 悲观锁 (Pessimistic Locking)
-- ============================================================

BEGIN TRANSACTION;
    SELECT * FROM accounts WITH (UPDLOCK, HOLDLOCK)
    WHERE id = 1;
    -- 其他事务无法修改该行直到当前事务结束
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- ============================================================
-- 应用锁 (Application Locks)
-- ============================================================

-- sp_getapplock: 获取应用级锁
BEGIN TRANSACTION;
    DECLARE @result INT;
    EXEC @result = sp_getapplock
        @Resource = 'my_lock',
        @LockMode = 'Exclusive',
        @LockOwner = 'Transaction',
        @LockTimeout = 5000;        -- 超时毫秒

    -- @result: 0=成功, 1=成功(等待后), -1=超时, -2=取消, -3=死锁
    IF @result >= 0
    BEGIN
        -- ... 执行需要互斥的操作 ...
        EXEC sp_releaseapplock @Resource = 'my_lock';
    END;
COMMIT;

-- LockMode 选项: Shared, Update, IntentShared, IntentExclusive, Exclusive
-- LockOwner 选项: Transaction (默认), Session

-- ============================================================
-- 死锁检测与预防
-- ============================================================

-- SQL Server 自动检测死锁，选择一个事务作为死锁牺牲者
-- 设置死锁优先级
SET DEADLOCK_PRIORITY LOW;      -- 优先被选为牺牲者
SET DEADLOCK_PRIORITY NORMAL;   -- 默认
SET DEADLOCK_PRIORITY HIGH;     -- 最后被选为牺牲者
SET DEADLOCK_PRIORITY 5;        -- -10 到 10 的数值

-- 锁超时
SET LOCK_TIMEOUT 5000;          -- 毫秒，-1 = 无限等待（默认）
SET LOCK_TIMEOUT 0;             -- 立即超时

-- 启用死锁跟踪标志
DBCC TRACEON(1222, -1);         -- 详细死锁信息写入错误日志

-- 使用扩展事件捕获死锁
CREATE EVENT SESSION deadlock_monitor
ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file(SET filename = N'deadlocks.xel');
ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = START;

-- ============================================================
-- 锁监控 (Lock Monitoring)
-- ============================================================

-- sys.dm_tran_locks: 查看当前所有锁
SELECT
    resource_type,
    resource_database_id,
    resource_associated_entity_id,
    request_mode,
    request_status,
    request_session_id
FROM sys.dm_tran_locks;

-- 查看锁等待
SELECT
    wt.session_id           AS waiting_session_id,
    wt.blocking_session_id,
    st1.text                AS waiting_query,
    st2.text                AS blocking_query,
    tl.resource_type,
    tl.request_mode
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_exec_sessions es
    ON wt.session_id = es.session_id
JOIN sys.dm_tran_locks tl
    ON wt.session_id = tl.request_session_id
CROSS APPLY sys.dm_exec_sql_text(es.most_recent_sql_handle) st1
OUTER APPLY sys.dm_exec_sql_text(
    (SELECT most_recent_sql_handle FROM sys.dm_exec_sessions
     WHERE session_id = wt.blocking_session_id)
) st2
WHERE wt.blocking_session_id IS NOT NULL;

-- sp_lock（旧版，不推荐）
EXEC sp_lock;

-- 活动监视器
-- SSMS -> Activity Monitor -> Processes / Resource Waits

-- ============================================================
-- 快照隔离 (Snapshot Isolation)
-- ============================================================

-- 启用数据库级别快照隔离（使用 tempdb 中的行版本存储）
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;

-- 使用快照隔离
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
    SELECT * FROM orders WHERE id = 100;  -- 读取事务开始时的快照
COMMIT;

-- READ_COMMITTED_SNAPSHOT: 使 READ COMMITTED 使用行版本
ALTER DATABASE MyDB SET READ_COMMITTED_SNAPSHOT ON;

-- 标准隔离级别
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
