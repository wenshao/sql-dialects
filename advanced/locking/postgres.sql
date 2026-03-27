-- PostgreSQL: 锁机制 (Locking)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Explicit Locking
--       https://www.postgresql.org/docs/current/explicit-locking.html
--   [2] PostgreSQL Documentation - Lock Management Functions
--       https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS
--   [3] PostgreSQL Documentation - The pg_locks View
--       https://www.postgresql.org/docs/current/view-pg-locks.html
--   [4] PostgreSQL Documentation - Transaction Isolation
--       https://www.postgresql.org/docs/current/transaction-iso.html

-- ============================================================
-- 行级锁 (Row-Level Locks)
-- ============================================================

-- SELECT FOR UPDATE: 排他锁，阻止其他事务修改或锁定选中的行
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

-- SELECT FOR NO KEY UPDATE: 较弱的排他锁，不阻塞 SELECT FOR KEY SHARE
-- （PostgreSQL 9.3+）
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;

-- SELECT FOR SHARE: 共享锁，阻止修改但允许其他 FOR SHARE
SELECT * FROM orders WHERE id = 100 FOR SHARE;

-- SELECT FOR KEY SHARE: 最弱的行锁，只阻止 DELETE 和主键修改
-- （PostgreSQL 9.3+）
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;

-- ============================================================
-- NOWAIT / SKIP LOCKED
-- ============================================================

-- NOWAIT: 无法立即获取锁时立即报错，不等待
SELECT * FROM orders WHERE status = 'pending'
FOR UPDATE NOWAIT;

-- SKIP LOCKED: 跳过已被锁定的行（PostgreSQL 9.5+）
-- 非常适合实现工作队列
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at
LIMIT 5
FOR UPDATE SKIP LOCKED;

-- ============================================================
-- 表级锁 (Table-Level Locks)
-- ============================================================

-- ACCESS SHARE: 最弱的表锁，只与 ACCESS EXCLUSIVE 冲突
-- (SELECT 自动获取)
LOCK TABLE orders IN ACCESS SHARE MODE;

-- ROW SHARE: 与 EXCLUSIVE/ACCESS EXCLUSIVE 冲突
-- (SELECT FOR UPDATE/SHARE 自动获取)
LOCK TABLE orders IN ROW SHARE MODE;

-- ROW EXCLUSIVE: UPDATE/DELETE/INSERT 自动获取
LOCK TABLE orders IN ROW EXCLUSIVE MODE;

-- SHARE UPDATE EXCLUSIVE: VACUUM/CREATE INDEX CONCURRENTLY 自动获取
LOCK TABLE orders IN SHARE UPDATE EXCLUSIVE MODE;

-- SHARE: 与写操作冲突
-- (CREATE INDEX 非 CONCURRENTLY 自动获取)
LOCK TABLE orders IN SHARE MODE;

-- SHARE ROW EXCLUSIVE
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;

-- EXCLUSIVE
LOCK TABLE orders IN EXCLUSIVE MODE;

-- ACCESS EXCLUSIVE: 最强的表锁，与所有其他锁冲突
-- (ALTER TABLE/DROP TABLE 自动获取)
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

-- NOWAIT 模式
LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;

-- ============================================================
-- 乐观锁 (Optimistic Locking)
-- ============================================================

-- 使用版本号列实现
ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

-- 更新时检查版本号
UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 如果受影响行数为 0，说明数据已被其他事务修改

-- 使用 xmin 系统列（PostgreSQL 特有的隐藏列）
SELECT id, xmin FROM orders WHERE id = 100;
-- 更新时检查 xmin 是否变化
UPDATE orders SET status = 'shipped'
WHERE id = 100 AND xmin = '12345';

-- ============================================================
-- 悲观锁 (Pessimistic Locking)
-- ============================================================

-- 典型悲观锁事务模式
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    -- 此时其他事务无法修改该行
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 咨询锁 / 应用锁 (Advisory Locks)
-- ============================================================

-- 会话级咨询锁（需要手动释放或等到会话结束）
SELECT pg_advisory_lock(12345);
-- ... 执行需要互斥的操作 ...
SELECT pg_advisory_unlock(12345);

-- 事务级咨询锁（事务结束时自动释放）
SELECT pg_advisory_xact_lock(12345);

-- 非阻塞版本（尝试获取，获取失败返回 false）
SELECT pg_try_advisory_lock(12345);

-- 双参数形式（两个 int4 组成锁标识）
SELECT pg_advisory_lock(100, 200);

-- 共享咨询锁
SELECT pg_advisory_lock_shared(12345);
SELECT pg_advisory_unlock_shared(12345);

-- ============================================================
-- 死锁检测与预防
-- ============================================================

-- PostgreSQL 自动检测死锁，默认超时 deadlock_timeout = 1s
SHOW deadlock_timeout;
SET deadlock_timeout = '2s';

-- 设置 lock_timeout 避免无限等待
SET lock_timeout = '5s';

-- 设置 statement_timeout 作为总体超时保障
SET statement_timeout = '30s';

-- 预防死锁：按固定顺序获取锁
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE; -- 先锁 id 较小的
    SELECT * FROM accounts WHERE id = 2 FOR UPDATE; -- 再锁 id 较大的
    -- ... 操作 ...
COMMIT;

-- ============================================================
-- 锁监控 (Lock Monitoring)
-- ============================================================

-- 查看当前所有锁
SELECT * FROM pg_locks;

-- 查看锁等待情况
SELECT
    blocked.pid     AS blocked_pid,
    blocked.query   AS blocked_query,
    blocking.pid    AS blocking_pid,
    blocking.query  AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid
JOIN pg_locks kl ON kl.locktype = bl.locktype
    AND kl.database IS NOT DISTINCT FROM bl.database
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.page IS NOT DISTINCT FROM bl.page
    AND kl.tuple IS NOT DISTINCT FROM bl.tuple
    AND kl.virtualxid IS NOT DISTINCT FROM bl.virtualxid
    AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
    AND kl.classid IS NOT DISTINCT FROM bl.classid
    AND kl.objid IS NOT DISTINCT FROM bl.objid
    AND kl.objsubid IS NOT DISTINCT FROM bl.objsubid
    AND kl.pid != bl.pid
JOIN pg_stat_activity blocking ON kl.pid = blocking.pid
WHERE NOT bl.granted;

-- pg_blocking_pids 函数（PostgreSQL 9.6+）
SELECT pid, pg_blocking_pids(pid), query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

-- 终止阻塞的进程
SELECT pg_terminate_backend(12345);

-- ============================================================
-- MVCC (多版本并发控制)
-- ============================================================

-- PostgreSQL 使用 MVCC，读操作不阻塞写操作，写操作不阻塞读操作
-- 事务隔离级别
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 注意：PostgreSQL 不支持 READ UNCOMMITTED（等同于 READ COMMITTED）
