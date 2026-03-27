-- YugabyteDB: 锁机制 (Locking)
--
-- 参考资料:
--   [1] YugabyteDB Documentation - Explicit Row-Level Locking
--       https://docs.yugabyte.com/latest/explore/transactions/explicit-locking/
--   [2] YugabyteDB Documentation - Transaction Isolation Levels
--       https://docs.yugabyte.com/latest/explore/transactions/isolation-levels/
--   [3] YugabyteDB Documentation - Concurrency Control
--       https://docs.yugabyte.com/latest/architecture/transactions/concurrency-control/

-- ============================================================
-- 行级锁（兼容 PostgreSQL）
-- ============================================================

SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;

-- NOWAIT
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

-- SKIP LOCKED
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;

-- ============================================================
-- 表级锁
-- ============================================================

-- YugabyteDB 支持 PostgreSQL 风格的 LOCK TABLE
LOCK TABLE orders IN ACCESS SHARE MODE;
LOCK TABLE orders IN ROW SHARE MODE;
LOCK TABLE orders IN ROW EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

-- ============================================================
-- 事务隔离级别
-- ============================================================

-- YugabyteDB 支持 Snapshot Isolation 和 Serializable
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;     -- 快照隔离
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;        -- 默认

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
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
-- 并发控制算法
-- ============================================================

-- Wait-on-Conflict: 事务等待冲突事务完成（默认，2.16+）
-- Fail-on-Conflict: 冲突时立即失败（旧行为）
-- 可通过 yb_enable_read_committed_isolation 配置

-- ============================================================
-- 死锁检测
-- ============================================================

-- YugabyteDB 分布式死锁检测
-- 自动检测并终止死锁事务

SET deadlock_timeout = '1s';
SET lock_timeout = '5s';

-- ============================================================
-- 锁监控
-- ============================================================

SELECT * FROM pg_locks;

-- 查看锁等待
SELECT pid, pg_blocking_pids(pid), query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

-- 终止后端进程
SELECT pg_terminate_backend(12345);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 兼容 PostgreSQL 语法
-- 2. 分布式架构：锁可能跨节点
-- 3. 支持分布式死锁检测
-- 4. 默认 SERIALIZABLE 隔离级别
-- 5. Wait-on-Conflict 模式减少事务重试
-- 6. 不支持 advisory locks（截至 2.x）
