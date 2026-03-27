-- TiDB: 锁机制 (Locking)
--
-- 参考资料:
--   [1] TiDB Documentation - Pessimistic Transaction Mode
--       https://docs.pingcap.com/tidb/stable/pessimistic-transaction
--   [2] TiDB Documentation - Optimistic Transaction Mode
--       https://docs.pingcap.com/tidb/stable/optimistic-transaction
--   [3] TiDB Documentation - LOCK STATS / Information Schema TIDB_TRX
--       https://docs.pingcap.com/tidb/stable/information-schema-tidb-trx
--   [4] TiDB Documentation - Deadlock
--       https://docs.pingcap.com/tidb/stable/information-schema-deadlocks

-- ============================================================
-- 行级锁 (Row-Level Locks) — 悲观模式
-- ============================================================

-- TiDB 4.0+ 默认使用悲观事务模式
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;       -- TiDB 6.0+
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;

-- NOWAIT (TiDB 5.0+)
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

-- SKIP LOCKED (TiDB 8.0+)
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;

-- ============================================================
-- 事务模式选择
-- ============================================================

-- 悲观事务模式（默认，TiDB 4.0+）
SET GLOBAL tidb_txn_mode = 'pessimistic';
SET SESSION tidb_txn_mode = 'pessimistic';

-- 乐观事务模式
SET SESSION tidb_txn_mode = 'optimistic';
-- 乐观模式下写冲突在 COMMIT 时才检测

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 悲观锁
-- ============================================================

BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 死锁检测
-- ============================================================

-- TiDB 自动检测死锁
-- 查看死锁历史
SELECT * FROM information_schema.DEADLOCKS;
-- TiDB 6.1+
SELECT * FROM information_schema.CLUSTER_DEADLOCKS;

-- 锁等待超时
SET GLOBAL innodb_lock_wait_timeout = 50;

-- ============================================================
-- 锁监控
-- ============================================================

-- 查看当前事务
SELECT * FROM information_schema.TIDB_TRX;
SELECT * FROM information_schema.CLUSTER_TIDB_TRX;

-- 查看数据锁（TiDB 5.3+）
SELECT * FROM information_schema.DATA_LOCK_WAITS;

-- 查看正在运行的查询
SHOW PROCESSLIST;

-- 终止会话
KILL connection_id;

-- ============================================================
-- 事务隔离级别
-- ============================================================

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- 默认（快照隔离）
-- TiDB 的 REPEATABLE READ 实际是快照隔离 (SI)
-- TiDB 不支持 SERIALIZABLE
