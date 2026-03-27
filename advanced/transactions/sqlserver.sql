-- SQL Server: 事务
--
-- 参考资料:
--   [1] SQL Server T-SQL - Transactions
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/transactions-transact-sql
--   [2] SQL Server - Transaction Isolation Levels
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql
--   [3] SQL Server - Lock Escalation
--       https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide

-- ============================================================
-- XACT_ABORT: 你几乎总应该 SET 它 ON
-- ============================================================
-- 放在最前面讲，因为这是 SQL Server 事务中最重要的设置
SET XACT_ABORT ON;

-- 没有 XACT_ABORT ON 时的行为:
--   BEGIN TRAN;
--   INSERT INTO orders (...) VALUES (...);     -- 成功
--   INSERT INTO order_items (...) VALUES (...); -- 失败 (约束违反)
--   COMMIT;                                     -- 居然成功了！只有 orders 被提交
--   -- 结果: 有订单但没有订单项，数据不一致
--
-- 有 XACT_ABORT ON 时的行为:
--   BEGIN TRAN;
--   INSERT INTO orders (...) VALUES (...);     -- 成功
--   INSERT INTO order_items (...) VALUES (...); -- 失败 → 自动 ROLLBACK 整个事务
--   -- 结果: 两条都没有提交，数据一致
--
-- 这就是为什么:
--   1. 几乎所有存储过程的第一行都应该是 SET XACT_ABORT ON
--   2. MERGE 语句之前必须 SET XACT_ABORT ON
--   3. 分布式事务(linked server)要求 XACT_ABORT ON
--
-- 不用 XACT_ABORT 的极少数场景: 你想捕获错误并做自定义处理

-- ============================================================
-- 基本事务
-- ============================================================
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
SAVE TRANSACTION sp_after_debit;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TRANSACTION sp_after_debit;  -- 只回滚到保存点
-- id=1 的修改保留，可以继续其他操作
COMMIT;

-- ============================================================
-- 标准错误处理模板
-- ============================================================
-- 这是 SQL Server 中最常用的事务错误处理模式
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRAN;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0    -- 检查是否有活跃事务
        ROLLBACK;

    -- 记录错误信息
    DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @sev INT = ERROR_SEVERITY();
    DECLARE @sta INT = ERROR_STATE();

    -- THROW (2012+): 重新抛出原始错误
    THROW;

    -- 或使用 RAISERROR 自定义错误消息 (所有版本)
    -- RAISERROR(@msg, @sev, @sta);
END CATCH;

-- 为什么 XACT_ABORT + TRY/CATCH 都需要:
--   XACT_ABORT: 保证事务级别的原子性（任何错误都回滚）
--   TRY/CATCH:  让你有机会记录日志、自定义错误消息、清理资源
--   单独用 XACT_ABORT: 错误直接抛给客户端，没有清理机会
--   单独用 TRY/CATCH:  某些错误（如死锁）不触发 CATCH，事务可能半提交

-- ============================================================
-- SNAPSHOT vs READ_COMMITTED_SNAPSHOT: 选择哪个
-- ============================================================
-- SQL Server 默认的 READ COMMITTED 使用锁：读阻塞写，写阻塞读
-- 这是 SQL Server 和 Oracle/PostgreSQL 最大的行为差异

-- 选项 1: READ_COMMITTED_SNAPSHOT (RCSI) — 推荐大多数应用
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
-- 效果: READ COMMITTED 的行为变成类似 Oracle 的 MVCC
--   - 读不阻塞写，写不阻塞读
--   - 读到的是语句开始时的一致性快照
--   - 不需要改任何应用代码！应用仍然使用 READ COMMITTED
--   - 代价: tempdb 压力增大（存储行版本），额外 14 字节/行开销
--
-- 这是微软官方推荐的做法，Azure SQL Database 默认开启 RCSI

-- 选项 2: SNAPSHOT ISOLATION — 特定场景
ALTER DATABASE mydb SET ALLOW_SNAPSHOT_ISOLATION ON;
-- 使用时需要显式设置:
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
SELECT SUM(balance) FROM accounts;            -- 看到事务开始时的快照
-- ... 中间无论其他会话怎么改 ...
SELECT COUNT(*) FROM accounts WHERE balance > 0;  -- 仍然是同一快照
COMMIT;

-- RCSI vs SNAPSHOT 的关键区别:
--   RCSI:     语句级快照（每条 SELECT 看到语句开始时的数据）
--   SNAPSHOT: 事务级快照（整个事务看到事务开始时的数据）
--
--   RCSI:     没有写冲突检测
--   SNAPSHOT: 有写冲突检测（两个事务改同一行 → 后提交者报错 3960）
--
--   选择指南:
--     大多数应用 → RCSI（零代码改动，立竿见影）
--     需要事务级一致性的报表 → SNAPSHOT
--     需要乐观并发控制 → SNAPSHOT

-- ============================================================
-- 隔离级别完整列表
-- ============================================================
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 脏读（等价于 NOLOCK 提示）
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 默认，加锁方式
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 持有 S 锁到事务结束
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 范围锁，防止幻读
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;           -- MVCC，需要先启用

-- READ UNCOMMITTED 实际使用场景:
--   唯一合理的用途: 快速估算行数或非精确报表
--   SELECT COUNT(*) FROM huge_table WITH (NOLOCK);
--   除此之外不要用！脏读导致的 bug 极难排查

-- ============================================================
-- 锁升级 (Lock Escalation): 行锁 → 表锁
-- ============================================================
-- SQL Server 的锁升级行为与 Oracle 完全不同
-- Oracle: 永远不升级（100万行 = 100万个行锁）
-- SQL Server: 当一个事务在同一个表上持有超过约 5000 个行/页锁时，
--             尝试升级为表锁
--
-- 锁升级的问题:
--   一旦升级为表锁，其他所有会话对该表的操作都被阻塞
--   大批量 UPDATE 或 DELETE 最容易触发

-- 方案 1: 禁用表级锁升级（但保留分区级升级）
ALTER TABLE large_table SET (LOCK_ESCALATION = DISABLE);
-- 注意: 禁用后内存使用量可能飙升（每个行锁占约 96 字节）
-- 100万行 = 约 96MB 的锁内存

-- 方案 2: 分区级升级 (2008+)
ALTER TABLE partitioned_table SET (LOCK_ESCALATION = AUTO);
-- AUTO: 分区表升级到分区锁而非表锁，影响范围小很多

-- 方案 3: 分批处理（推荐，从源头解决）
-- 不要一次 UPDATE 100万行，分批每次 5000 行:
DECLARE @batch_size INT = 5000;
DECLARE @rows_affected INT = 1;
WHILE @rows_affected > 0
BEGIN
    UPDATE TOP (@batch_size) orders
    SET status = 'archived'
    WHERE order_date < '2023-01-01' AND status != 'archived';

    SET @rows_affected = @@ROWCOUNT;
    -- 可选: 每批之间 WAITFOR DELAY 让其他事务有机会执行
END;

-- ============================================================
-- 死锁诊断
-- ============================================================
-- 死锁是 SQL Server 中最常见的并发问题之一

-- 1. 启用跟踪标志（全局）
DBCC TRACEON(1222, -1);  -- 将死锁信息写入错误日志
-- 1204: 旧格式（文本）  1222: 新格式（XML，更详细）

-- 2. Extended Events (2012+, 推荐)
CREATE EVENT SESSION deadlock_monitor
ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file (
    SET filename = N'C:\deadlocks\deadlock_monitor.xel',
        max_file_size = 50  -- MB
)
WITH (MAX_MEMORY = 4096 KB, STARTUP_STATE = ON);
ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = START;

-- 3. 查看最近的死锁（通过 system_health 默认会话）
SELECT
    xed.value('@timestamp', 'datetime2') AS deadlock_time,
    xed.query('.') AS deadlock_graph
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_session_targets st
    JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
    WHERE s.name = 'system_health'
      AND st.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS xed(xed);

-- 减少死锁的策略:
--   1. 所有事务按相同顺序访问表（最重要）
--   2. 事务尽量短: 减少持有锁的时间
--   3. 使用合适的索引: 减少锁定的行数
--   4. RCSI/SNAPSHOT: 读不加锁，消除读写死锁
--   5. SET DEADLOCK_PRIORITY LOW: 让当前会话成为死锁牺牲者

-- ============================================================
-- 自动提交 vs 隐式事务
-- ============================================================
-- SQL Server 默认是自动提交: 每条语句是独立事务
-- 这与 Oracle（必须显式 COMMIT）完全不同

SET IMPLICIT_TRANSACTIONS ON;
-- 开启后行为类似 Oracle: DML 自动开启事务，需要显式 COMMIT
-- 很少使用，大多数人习惯显式 BEGIN TRAN
SET IMPLICIT_TRANSACTIONS OFF;  -- 恢复自动提交

-- ============================================================
-- 锁提示 (Locking Hints)
-- ============================================================
SELECT * FROM accounts WITH (UPDLOCK) WHERE id = 1;          -- 更新锁
SELECT * FROM accounts WITH (XLOCK) WHERE id = 1;            -- 排他锁
SELECT * FROM accounts WITH (HOLDLOCK) WHERE id = 1;         -- 保持到事务结束
SELECT * FROM accounts WITH (NOLOCK) WHERE id = 1;           -- 脏读
SELECT * FROM accounts WITH (ROWLOCK) WHERE id = 1;          -- 强制行锁
SELECT * FROM accounts WITH (TABLOCK) WHERE id = 1;          -- 表锁
SELECT * FROM accounts WITH (UPDLOCK, ROWLOCK) WHERE id = 1; -- 组合

-- NOLOCK 的诱惑与代价:
--   优点: 不加锁，不被阻塞，报表查询"看起来"快了
--   代价: 可能读到脏数据、幻影行、甚至跳过行或重复读行
--         （页分裂期间 NOLOCK 扫描可能跳行或重复行）
--   正确替代: 开启 RCSI，读不加锁但数据一致

-- ============================================================
-- 分布式事务 (MSDTC)
-- ============================================================
-- 跨服务器/数据库的事务需要 MSDTC (Microsoft Distributed Transaction Coordinator)
BEGIN DISTRIBUTED TRANSACTION;
    UPDATE local_db.dbo.accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE remote_server.remote_db.dbo.accounts SET balance = balance + 100 WHERE id = 1;
COMMIT;
-- 前提: 两台服务器都要配置并启动 MSDTC 服务
-- 注意: 分布式事务性能差，尽量避免；考虑用消息队列替代

-- ============================================================
-- 延迟持久性 (Delayed Durability, 2014+)
-- ============================================================
-- 正常 COMMIT: 等待 redo 日志写入磁盘（保证持久性）
-- 延迟 COMMIT: 日志写入内存缓冲即返回，后台异步刷盘

ALTER DATABASE mydb SET DELAYED_DURABILITY = ALLOWED;
-- 然后在事务中:
BEGIN TRAN;
    INSERT INTO telemetry (data, ts) VALUES ('sensor_reading', GETDATE());
COMMIT WITH (DELAYED_DURABILITY = ON);

-- 性能提升: 高频小事务场景下吞吐量可提升 2-4 倍
-- 风险: 掉电时最近几毫秒的已"提交"事务可能丢失
-- 适用: 遥测数据、日志、Session 状态等可容忍少量丢失的场景
-- 不适用: 金融交易、订单等要求严格持久性的场景

-- ============================================================
-- 诊断视图
-- ============================================================
-- 当前锁
SELECT resource_type, resource_description, request_mode, request_status
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID;

-- 阻塞链
SELECT
    blocked.session_id AS blocked_spid,
    blocker.session_id AS blocker_spid,
    blocked.wait_type,
    blocked.wait_time / 1000.0 AS wait_seconds,
    blocker_sql.text AS blocker_sql
FROM sys.dm_exec_requests blocked
JOIN sys.dm_exec_sessions blocker ON blocked.blocking_session_id = blocker.session_id
CROSS APPLY sys.dm_exec_sql_text(blocker.most_recent_sql_handle) blocker_sql
WHERE blocked.blocking_session_id > 0;

-- 当前隔离级别
DBCC USEROPTIONS;
-- 或:
SELECT CASE transaction_isolation_level
    WHEN 0 THEN 'Unspecified'
    WHEN 1 THEN 'ReadUncommitted'
    WHEN 2 THEN 'ReadCommitted'
    WHEN 3 THEN 'RepeatableRead'
    WHEN 4 THEN 'Serializable'
    WHEN 5 THEN 'Snapshot'
END AS isolation_level
FROM sys.dm_exec_sessions
WHERE session_id = @@SPID;

-- ============================================================
-- 注意事项总结
-- ============================================================
-- 1. 始终 SET XACT_ABORT ON（防止部分提交）
-- 2. 始终使用 TRY/CATCH + @@TRANCOUNT 检查（防止悬挂事务）
-- 3. DDL 是事务性的: CREATE/ALTER/DROP 可以回滚（Oracle 不行!）
-- 4. 认真考虑 RCSI: 大多数应用开启 RCSI 后并发性能显著提升
-- 5. NOLOCK 不是性能优化手段，是数据一致性炸弹
-- 6. 事务尽量短: 长事务 + 锁 = 阻塞链 → 整个系统停摆

-- ============================================================
-- 横向对比: SQL Server vs 其他方言
-- ============================================================

-- 默认并发模型对比（SQL Server 最大的特殊之处）:
--   SQL Server: 默认 READ COMMITTED 用锁（读阻塞写，写阻塞读）→ 开启 RCSI 才用 MVCC
--   PostgreSQL: 默认就是 MVCC（读写不互相阻塞，从一开始就这样）
--   Oracle:     默认就是 MVCC（和 PostgreSQL 类似）
--   MySQL:      InnoDB 默认 MVCC（REPEATABLE READ 级别）
--   结论: SQL Server 是主流数据库中唯一默认用锁做读一致性的，强烈建议开启 RCSI

-- XACT_ABORT 对比（SQL Server 独有的概念）:
--   SQL Server: 默认 XACT_ABORT OFF，错误不自动回滚事务（部分提交风险！）
--               需要手动 SET XACT_ABORT ON
--   PostgreSQL: 任何错误自动将事务标记为 aborted，后续语句全部失败（更安全）
--   Oracle:     错误不自动回滚，但可以继续执行（需要 EXCEPTION 处理）
--   MySQL:      错误不自动回滚事务（和 SQL Server XACT_ABORT OFF 类似）

-- 事务语法对比:
--   SQL Server: BEGIN TRAN ... COMMIT / ROLLBACK（T-SQL 风格）
--   PostgreSQL: BEGIN ... COMMIT / ROLLBACK（SQL 标准风格）
--   Oracle:     DML 自动开启事务，只需 COMMIT / ROLLBACK（没有显式 BEGIN）
--   MySQL:      START TRANSACTION ... COMMIT / ROLLBACK

-- DDL 事务性对比:
--   SQL Server: DDL 事务性（CREATE/ALTER/DROP 可以回滚）
--   PostgreSQL: DDL 事务性（同 SQL Server）
--   Oracle:     DDL 隐式提交（不能回滚！）
--   MySQL:      DDL 隐式提交（不能回滚！）

-- 锁升级对比:
--   SQL Server: 行锁超过约 5000 个时自动升级为表锁（可能导致阻塞风暴）
--   PostgreSQL: 不做锁升级（100 万行 = 100 万个行锁，用共享内存管理）
--   Oracle:     不做锁升级（与 PostgreSQL 相同策略）
--   MySQL:      InnoDB 不做锁升级（行锁由存储引擎管理）

-- 锁提示对比:
--   SQL Server: WITH (NOLOCK/UPDLOCK/XLOCK/HOLDLOCK/ROWLOCK/TABLOCK...)（最丰富）
--   PostgreSQL: FOR UPDATE / FOR SHARE / NOWAIT / SKIP LOCKED（标准 SQL 方式）
--   Oracle:     FOR UPDATE NOWAIT / SKIP LOCKED（简洁）
--   MySQL:      FOR UPDATE / FOR SHARE / NOWAIT / SKIP LOCKED（8.0+，和 PostgreSQL 类似）

-- 死锁处理对比:
--   SQL Server: 自动检测，选择开销最小的事务回滚（可用 DEADLOCK_PRIORITY 调整）
--   PostgreSQL: 自动检测，回滚最后获取锁的事务
--   Oracle:     自动检测，只回滚导致死锁的那条语句（不回滚事务！）
--   MySQL:      InnoDB 自动检测，回滚最小的事务（按 undo log 量）

-- 延迟持久性对比（SQL Server 2014+ 独有功能）:
--   SQL Server: DELAYED_DURABILITY，COMMIT 不等待日志刷盘，吞吐量提升 2-4 倍
--   PostgreSQL: synchronous_commit = off（类似效果，但是会话级设置）
--   Oracle:     COMMIT NOWAIT（10g+，类似效果）
--   MySQL:      innodb_flush_log_at_trx_commit = 2（类似效果，组提交）

-- 分布式事务对比:
--   SQL Server: MSDTC（操作系统级服务，配置复杂但功能强大）
--   PostgreSQL: PREPARE TRANSACTION（内置 2PC 协议）
--   Oracle:     DBMS_XA / XA 接口
--   MySQL:      XA PREPARE / XA COMMIT（XA 协议）

-- 错误处理对比:
--   SQL Server: TRY/CATCH + XACT_ABORT（最像编程语言的错误处理）
--   PostgreSQL: EXCEPTION 块（在 PL/pgSQL 中，自动创建隐式 SAVEPOINT）
--   Oracle:     EXCEPTION 块（PL/SQL 中，最成熟）
--   MySQL:      DECLARE HANDLER（存储过程中，语法较特殊）
