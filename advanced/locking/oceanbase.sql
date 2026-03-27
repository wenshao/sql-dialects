-- OceanBase: 锁机制 (Locking)
--
-- 参考资料:
--   [1] OceanBase 文档 - 事务管理
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001577255
--   [2] OceanBase 文档 - 锁管理
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001577256

-- ============================================================
-- OceanBase 并发模型
-- ============================================================
-- OceanBase 支持两种模式: MySQL 兼容模式和 Oracle 兼容模式
-- 锁机制取决于所选的兼容模式

-- ============================================================
-- MySQL 兼容模式
-- ============================================================

-- SELECT FOR UPDATE
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;

-- NOWAIT / SKIP LOCKED (OceanBase 4.0+)
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;

-- 表级锁
LOCK TABLES orders READ;
LOCK TABLES orders WRITE;
UNLOCK TABLES;

-- ============================================================
-- Oracle 兼容模式
-- ============================================================

-- SELECT FOR UPDATE
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
SELECT * FROM orders WHERE id = 100 FOR UPDATE WAIT 5;
SELECT * FROM orders WHERE id = 100 FOR UPDATE SKIP LOCKED;

-- 表级锁
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD version INT DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 悲观锁
-- ============================================================

START TRANSACTION;  -- MySQL 模式
-- BEGIN;          -- Oracle 模式
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 死锁检测
-- ============================================================

-- OceanBase 自动检测死锁
-- 锁等待超时
SET ob_trx_lock_timeout = 10000000;  -- 微秒

-- ============================================================
-- 锁监控
-- ============================================================

-- 查看锁等待（MySQL 模式）
SELECT * FROM oceanbase.GV$OB_LOCKS;
SELECT * FROM oceanbase.V$OB_LOCKS;

-- 查看活跃事务
SELECT * FROM oceanbase.GV$OB_TRANSACTION_PARTICIPANTS;

-- ============================================================
-- 事务隔离级别
-- ============================================================

-- MySQL 模式
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Oracle 模式
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 锁行为取决于兼容模式 (MySQL/Oracle)
-- 2. 支持行级锁和表级锁
-- 3. MVCC 实现并发控制
-- 4. 分布式事务使用两阶段提交
-- 5. 不支持 advisory locks
