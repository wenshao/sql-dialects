-- Apache Derby: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Apache Derby Documentation - Locking, Concurrency, and Isolation
--       https://db.apache.org/derby/docs/10.16/devguide/cdevconcepts15366.html
--   [2] Apache Derby Documentation - Lock Granularity
--       https://db.apache.org/derby/docs/10.16/devguide/cdevconcepts36402.html
--   [3] Apache Derby Documentation - LOCK TABLE
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj40506.html

-- ============================================================
-- 行级锁
-- ============================================================

-- SELECT FOR UPDATE
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT id, status FROM orders WHERE id = 100 FOR UPDATE OF status;

-- FOR READ ONLY
SELECT * FROM orders FOR READ ONLY;

-- ============================================================
-- 表级锁
-- ============================================================

LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;

-- ============================================================
-- 隔离级别
-- ============================================================

-- Derby 使用 WITH 子句设置语句级隔离
-- CS = Cursor Stability (READ COMMITTED) -- 默认
-- RR = Repeatable Read (SERIALIZABLE)
-- RS = Read Stability (REPEATABLE READ)
-- UR = Uncommitted Read (READ UNCOMMITTED)

SELECT * FROM orders WITH CS;
SELECT * FROM orders WITH RR;
SELECT * FROM orders WITH RS;
SELECT * FROM orders WITH UR;

-- 连接级隔离
-- SET ISOLATION = CS | RR | RS | UR
-- 通过 JDBC: connection.setTransactionIsolation(...)

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INTEGER DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 悲观锁
-- ============================================================

-- 自动提交需要先关闭
-- connection.setAutoCommit(false);

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 死锁与锁超时
-- ============================================================

-- 死锁超时设置
-- derby.locks.deadlockTimeout = 20  (默认 20 秒)
-- derby.locks.waitTimeout = 60      (默认 60 秒)

-- Derby 自动检测死锁并选择一个事务终止

-- ============================================================
-- 锁监控
-- ============================================================

-- 通过 SYSCS_UTIL 过程
-- SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY('derby.locks.monitor', 'true');
-- SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY('derby.locks.deadlockTrace', 'true');

-- 锁表视图（需要启用 derby.locks.monitor）
SELECT * FROM SYSCS_DIAG.LOCK_TABLE;

-- 事务表
SELECT * FROM SYSCS_DIAG.TRANSACTION_TABLE;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 支持行级锁和表级锁
-- 2. 锁可能从行级升级到表级
-- 3. 不支持 NOWAIT / SKIP LOCKED
-- 4. 不支持 advisory locks
-- 5. 嵌入式模式下单进程使用
