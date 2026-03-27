-- Amazon Redshift: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Amazon Redshift Documentation - Managing Concurrent Write Operations
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Concurrent_writes.html
--   [2] Amazon Redshift Documentation - STV_LOCKS
--       https://docs.aws.amazon.com/redshift/latest/dg/r_STV_LOCKS.html
--   [3] Amazon Redshift Documentation - LOCK
--       https://docs.aws.amazon.com/redshift/latest/dg/r_LOCK.html
--   [4] Amazon Redshift Documentation - Serializable Isolation
--       https://docs.aws.amazon.com/redshift/latest/dg/c_serial_isolation.html

-- ============================================================
-- Redshift 并发模型概述
-- ============================================================
-- Redshift 使用快照隔离 + 序列化一致性:
-- 1. 默认隔离级别是 SERIALIZABLE
-- 2. 读操作使用 MVCC 快照，不阻塞写
-- 3. 写操作获取表级锁
-- 4. 不支持行级锁
-- 5. 不支持 SELECT FOR UPDATE / FOR SHARE

-- ============================================================
-- 表级锁
-- ============================================================

-- LOCK 命令
LOCK TABLE orders;                           -- 默认 ACCESS EXCLUSIVE
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;  -- 排他锁
LOCK TABLE orders IN EXCLUSIVE MODE;

-- 注意：Redshift 不支持 SHARE 模式的 LOCK
-- 写操作（INSERT/UPDATE/DELETE/COPY）自动获取写锁
-- DDL 操作获取 ACCESS EXCLUSIVE 锁

-- ============================================================
-- 并发写入行为
-- ============================================================

-- Redshift 使用可序列化隔离
-- 并发事务如果产生序列化冲突会被终止
-- 错误: ERROR: 1023 DETAIL: Serializable isolation violation on table

-- 并发写入同一表的建议:
-- 1. 使用 COPY 替代多个 INSERT
-- 2. 在低峰期执行大批量写入
-- 3. 减少事务持有时间

-- ============================================================
-- 乐观锁
-- ============================================================

-- Redshift 内部使用乐观并发控制
-- 事务在提交时验证是否有序列化冲突

-- 应用层乐观锁
CREATE TABLE orders (
    id         INTEGER NOT NULL,
    status     VARCHAR(50),
    version    INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT GETDATE()
);

UPDATE orders
SET status = 'shipped',
    version = version + 1,
    updated_at = GETDATE()
WHERE id = 100 AND version = 5;

-- ============================================================
-- 锁超时
-- ============================================================

-- 设置锁超时（statement_timeout 参数）
SET statement_timeout TO 60000;  -- 毫秒

-- 死锁超时
SET deadlock_timeout TO 1000;    -- 毫秒，默认

-- ============================================================
-- 锁监控
-- ============================================================

-- STV_LOCKS: 查看当前锁
SELECT * FROM STV_LOCKS;

-- 查看锁持有者
SELECT
    l.table_id,
    t.name AS table_name,
    l.lock_owner,
    l.lock_owner_pid,
    l.lock_status
FROM STV_LOCKS l
JOIN STV_TBL_PERM t ON l.table_id = t.id
ORDER BY l.table_id;

-- 查看运行中的事务
SELECT
    xid,
    pid,
    txn_owner,
    txn_db,
    starttime,
    DATEDIFF(second, starttime, GETDATE()) AS duration_sec
FROM STV_TBL_TRANS
WHERE xid > 0
ORDER BY starttime;

-- 查看等待中的查询
SELECT
    w.query   AS waiting_query,
    w.starttime,
    w.text    AS waiting_text,
    b.query   AS blocking_query,
    b.text    AS blocking_text
FROM stl_querytext w
JOIN STV_LOCKS l ON w.query = l.lock_owner_pid
JOIN stl_querytext b ON l.lock_owner = b.query
WHERE l.lock_status = 'Waiting';

-- STL_TR_CONFLICT: 查看事务冲突
SELECT * FROM STL_TR_CONFLICT
ORDER BY xact_start_ts DESC
LIMIT 20;

-- 终止会话
SELECT PG_TERMINATE_BACKEND(pid);

-- ============================================================
-- 并发管理最佳实践
-- ============================================================

-- 1. 使用 WLM (Workload Management) 管理并发查询
-- 2. COPY 命令是加载数据的最佳方式（单次操作）
-- 3. 避免长时间运行的事务
-- 4. 使用 COMMIT 频率来控制锁持有时间
-- 5. 对于 ETL 工作负载，使用 staging 表 + INSERT INTO ... SELECT

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持行级锁
-- 3. 不支持 advisory locks
-- 4. 只有 SERIALIZABLE 隔离级别
-- 5. 并发写入冲突会导致事务被终止
-- 6. VACUUM/ANALYZE 操作不获取排他锁
