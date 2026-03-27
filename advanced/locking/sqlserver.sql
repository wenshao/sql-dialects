-- SQL Server: 锁机制（Lock Hints + 锁升级 + 快照隔离）
--
-- 参考资料:
--   [1] SQL Server - Locking and Row Versioning Guide
--       https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide

-- ============================================================
-- 1. 锁提示系统: SQL Server 最独特的并发控制机制
-- ============================================================

-- SQL Server 允许在查询中通过 WITH (...) 指定锁行为——这是其他数据库没有的。
SELECT * FROM orders WITH (NOLOCK) WHERE status = 'pending';        -- 不获取锁
SELECT * FROM orders WITH (HOLDLOCK) WHERE id = 100;                -- 持锁到事务结束
SELECT * FROM orders WITH (UPDLOCK) WHERE id = 100;                 -- 更新锁
SELECT * FROM orders WITH (XLOCK) WHERE id = 100;                   -- 排他锁
SELECT * FROM orders WITH (ROWLOCK, UPDLOCK) WHERE id = 100;        -- 强制行锁+更新锁
SELECT * FROM orders WITH (PAGLOCK) WHERE status = 'pending';       -- 强制页锁
SELECT * FROM orders WITH (TABLOCK);                                -- 表级共享锁
SELECT * FROM orders WITH (TABLOCKX);                               -- 表级排他锁
SELECT * FROM orders WITH (READPAST, UPDLOCK) WHERE status = 'pending'; -- 跳过被锁行
SELECT * FROM orders WITH (NOWAIT) WHERE id = 100;                  -- 获取不到锁立即报错

-- 设计分析（对引擎开发者）:
--   SQL Server 的锁提示是 T-SQL 与 SQL 标准最大的偏离之一。
--   其他数据库使用 SELECT ... FOR UPDATE 实现悲观锁:
--     PostgreSQL: SELECT * FROM t WHERE id = 1 FOR UPDATE
--     MySQL:      SELECT * FROM t WHERE id = 1 FOR UPDATE
--     Oracle:     SELECT * FROM t WHERE id = 1 FOR UPDATE
--   SQL Server 不支持 FOR UPDATE（唯一不支持的主流数据库）。
--
--   锁提示的优势: 更精细的控制（可以指定锁粒度: 行/页/表）
--   锁提示的劣势: 非标准、学习曲线陡、容易误用（尤其是 NOLOCK）

-- ============================================================
-- 2. WITH (NOLOCK) 文化及其危害
-- ============================================================

-- NOLOCK 是 SQL Server 生态中最广泛使用（和滥用）的提示。
-- 它等价于 READ UNCOMMITTED 隔离级别。

-- 为什么 NOLOCK 如此流行:
--   SQL Server 默认 READ COMMITTED + 共享锁模型：读操作获取 S 锁，
--   S 锁与写操作的 X 锁冲突 → 读写互斥 → 长查询阻塞 DML。
--   DBA 的"快速修复": 加 NOLOCK → 读不获取锁 → 不阻塞。

-- NOLOCK 的实际风险:
--   (1) 脏读: 读到未提交的数据
--   (2) 页分裂期间重复读或跳行（最危险，聚合结果可能偏差数个百分点）
--   (3) 读到半更新的行（宽行跨页时）

-- 正确解决方案: READ_COMMITTED_SNAPSHOT
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
-- 此后 READ COMMITTED 使用行版本（类似 PostgreSQL 的 MVCC）——读不阻塞写

-- 对引擎开发者的启示:
--   MVCC 应该是默认行为——PostgreSQL 从第一天就是 MVCC。
--   SQL Server 的锁模型是历史遗留，READ_COMMITTED_SNAPSHOT 是后来的修补。
--   新引擎不应该重复这个错误——默认使用 MVCC。

-- ============================================================
-- 3. 锁升级: SQL Server 独有机制
-- ============================================================

-- 当单个事务在一个表上持有超过约 5000 个行/页锁时，
-- SQL Server 自动将它们升级为表锁（减少锁管理器内存开销）。
-- 副作用: 表锁阻塞所有并发访问。

-- 控制锁升级:
ALTER TABLE orders SET (LOCK_ESCALATION = TABLE);    -- 默认：直接升级到表锁
ALTER TABLE orders SET (LOCK_ESCALATION = DISABLE);  -- 禁用升级（锁管理器压力大）
ALTER TABLE orders SET (LOCK_ESCALATION = AUTO);     -- 分区表：逐分区升级

-- 横向对比:
--   PostgreSQL: 无锁升级机制（行锁永远是行锁）
--   MySQL:      无锁升级（InnoDB 只有行锁和表锁，无中间级别）
--   Oracle:     无锁升级（行锁永远是行锁）

-- ============================================================
-- 4. 行级锁: SELECT FOR UPDATE 的 SQL Server 等价
-- ============================================================

BEGIN TRANSACTION;
    SELECT * FROM accounts WITH (UPDLOCK, ROWLOCK)
    WHERE id = 1;                     -- 等价于 SELECT ... FOR UPDATE
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- UPDLOCK vs XLOCK:
--   UPDLOCK: 允许其他事务读（S 锁兼容），但不允许其他事务也获取 U 锁
--   XLOCK:   不允许任何其他锁
-- UPDLOCK 是防止"转换死锁"的关键——两个事务同时获取 S 锁再试图升级为 X 锁。

-- ============================================================
-- 5. 应用锁（sp_getapplock）
-- ============================================================

BEGIN TRANSACTION;
    DECLARE @result INT;
    EXEC @result = sp_getapplock
        @Resource = 'process_order_123',
        @LockMode = 'Exclusive',
        @LockTimeout = 5000;
    IF @result >= 0
    BEGIN
        -- 执行需要互斥的操作
        EXEC sp_releaseapplock @Resource = 'process_order_123';
    END;
COMMIT;

-- 设计分析: 应用锁是逻辑锁（不绑定到任何数据库对象），
-- 用于实现跨表、跨操作的互斥。PostgreSQL 的等价: pg_advisory_lock。

-- ============================================================
-- 6. 死锁处理
-- ============================================================

SET DEADLOCK_PRIORITY LOW;     -- 优先被选为牺牲者
SET DEADLOCK_PRIORITY HIGH;    -- 最后被选为牺牲者
SET LOCK_TIMEOUT 5000;         -- 等锁超时（毫秒），-1 = 无限等待（默认）

-- 扩展事件捕获死锁:
CREATE EVENT SESSION deadlock_monitor ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file(SET filename = N'deadlocks.xel');
ALTER EVENT SESSION deadlock_monitor ON SERVER STATE = START;

-- ============================================================
-- 7. 快照隔离（SNAPSHOT ISOLATION）
-- ============================================================

ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;

SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
    SELECT * FROM orders WHERE id = 100;  -- 读取事务开始时的快照
COMMIT;

-- SNAPSHOT vs READ_COMMITTED_SNAPSHOT:
--   SNAPSHOT:                  事务级快照（事务开始时拍快照，整个事务看到一致视图）
--   READ_COMMITTED_SNAPSHOT:   语句级快照（每条语句看到语句开始时的数据）
--
-- PostgreSQL 的等价:
--   REPEATABLE READ → SQL Server SNAPSHOT
--   READ COMMITTED  → SQL Server READ_COMMITTED_SNAPSHOT

-- ============================================================
-- 8. 锁监控
-- ============================================================

-- 当前所有锁
SELECT resource_type, request_mode, request_status, request_session_id
FROM sys.dm_tran_locks;

-- 锁等待链
SELECT wt.session_id AS waiting, wt.blocking_session_id AS blocking,
       t.text AS waiting_query
FROM sys.dm_os_waiting_tasks wt
CROSS APPLY sys.dm_exec_sql_text(
    (SELECT most_recent_sql_handle FROM sys.dm_exec_sessions
     WHERE session_id = wt.session_id)
) t
WHERE wt.blocking_session_id IS NOT NULL;
