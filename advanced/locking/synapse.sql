-- Azure Synapse Analytics: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Azure Synapse Documentation - Transactions
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-develop-transactions
--   [2] Azure Synapse Documentation - Concurrency and Workload Management
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-develop-concurrency

-- ============================================================
-- Synapse 并发模型概述
-- ============================================================
-- Azure Synapse (Dedicated SQL Pool) 是 MPP 数据仓库:
-- 1. 支持事务（隐式和显式）
-- 2. 使用表级别和分区级别的锁
-- 3. 不支持行级锁
-- 4. 使用快照隔离（默认开启 READ_COMMITTED_SNAPSHOT）

-- ============================================================
-- 锁提示（兼容 SQL Server 子集）
-- ============================================================

-- NOLOCK（脏读）
SELECT * FROM orders WITH (NOLOCK) WHERE status = 'pending';

-- TABLOCK
SELECT * FROM orders WITH (TABLOCK);

-- 注意：Synapse 不支持所有 SQL Server 锁提示
-- 不支持: ROWLOCK, PAGLOCK, UPDLOCK, HOLDLOCK, XLOCK

-- ============================================================
-- 事务
-- ============================================================

BEGIN TRANSACTION;
    INSERT INTO orders VALUES (1, 'new', 100.00);
    UPDATE orders SET status = 'confirmed' WHERE id = 1;
COMMIT;

-- 隐式事务
-- 每个语句自动在事务中执行

-- LABEL（用于识别事务）
BEGIN TRANSACTION order_update;
    UPDATE orders SET status = 'shipped' WHERE id = 100;
COMMIT TRANSACTION order_update;

-- ============================================================
-- 最小日志操作
-- ============================================================

-- CTAS 是推荐的大批量写入方式（最少锁争用）
CREATE TABLE orders_new
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED COLUMNSTORE INDEX
)
AS SELECT * FROM orders WHERE status != 'cancelled';

-- RENAME 是原子操作
RENAME OBJECT orders TO orders_old;
RENAME OBJECT orders_new TO orders;

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD version INT NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 锁监控
-- ============================================================

-- sys.dm_pdw_waits: 查看等待
SELECT * FROM sys.dm_pdw_waits WHERE state = 'Queued';

-- sys.dm_tran_locks
SELECT * FROM sys.dm_tran_locks;

-- sys.dm_pdw_exec_sessions: 活跃会话
SELECT * FROM sys.dm_pdw_exec_sessions WHERE status = 'Active';

-- 终止查询
KILL 'request_id';

-- ============================================================
-- 并发管理
-- ============================================================

-- Synapse 有并发查询槽限制（默认 32 个并发查询）
-- 使用 Workload Management 管理查询优先级

-- 工作负载分类器
CREATE WORKLOAD CLASSIFIER wc_high_priority
WITH (
    WORKLOAD_GROUP = 'xlargerc',
    MEMBERNAME = 'high_priority_user',
    IMPORTANCE = HIGH
);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持行级锁
-- 2. 不支持 SELECT FOR UPDATE
-- 3. 锁提示支持有限（主要支持 NOLOCK/TABLOCK）
-- 4. 推荐使用 CTAS + RENAME 代替大批量 UPDATE
-- 5. 并发查询数有上限
-- 6. 默认启用 READ_COMMITTED_SNAPSHOT
