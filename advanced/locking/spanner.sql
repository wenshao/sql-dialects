-- Google Cloud Spanner: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Spanner Documentation - Transactions
--       https://cloud.google.com/spanner/docs/transactions
--   [2] Spanner Documentation - Lock Statistics
--       https://cloud.google.com/spanner/docs/lock-statistics
--   [3] Spanner Documentation - TrueTime and External Consistency
--       https://cloud.google.com/spanner/docs/true-time-external-consistency

-- ============================================================
-- Spanner 并发模型概述
-- ============================================================
-- Spanner 使用 TrueTime + 两阶段锁:
-- 1. 读写事务获取行级/范围锁
-- 2. 只读事务使用快照读，不需要锁
-- 3. 支持外部一致性（最强的一致性保证）
-- 4. 使用 wound-wait 算法防止死锁

-- ============================================================
-- 读写事务（自动获取锁）
-- ============================================================

-- Spanner 不使用 SELECT FOR UPDATE 语法
-- 读写事务中的所有读取自动获取共享锁
-- 写操作自动获取排他锁

-- 在客户端 SDK 中使用读写事务:
-- spanner_client.run_in_transaction(lambda txn: ...)

-- SQL DML 在读写事务中执行
BEGIN TRANSACTION;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 只读事务（无锁）
-- ============================================================

-- 只读事务使用快照，不获取锁
-- 强一致性读（读取最新数据）
SET TRANSACTION READ ONLY;
SELECT * FROM orders WHERE id = 100;
COMMIT;

-- 过时读（stale read）: 读取指定时间的数据快照
-- 在客户端 SDK 中指定时间戳:
-- txn = db.snapshot(exact_staleness=datetime.timedelta(seconds=15))

-- ============================================================
-- 锁类型
-- ============================================================

-- Spanner 使用以下锁类型:
-- Shared Lock (S): 读写事务的读取操作获取
-- Exclusive Lock (X): 写操作获取
-- Spanner 锁的粒度: 行级 + cell 级（列族/列）

-- 范围锁: 对主键范围加锁，防止幻读
-- 在读写事务中:
SELECT * FROM orders WHERE user_id = 100;
-- 这会在 user_id = 100 的范围上加共享锁

-- ============================================================
-- 死锁预防
-- ============================================================

-- Spanner 使用 wound-wait 算法:
-- 较早的事务可以 "伤害" 较晚的事务（终止它）
-- 较晚的事务会等待较早的事务
-- 这保证了不会产生死锁

-- 事务超时（默认 10 秒，客户端可配置）
-- 如果事务执行时间过长，会自动终止

-- ============================================================
-- 锁监控
-- ============================================================

-- 锁统计表（SPANNER_SYS schema）
SELECT * FROM SPANNER_SYS.LOCK_STATS_TOP_10MINUTE
ORDER BY LOCK_WAIT_SECONDS DESC;

-- 查看锁等待时间
SELECT
    ROW_RANGE_START_KEY,
    LOCK_WAIT_SECONDS,
    SAMPLE_LOCK_REQUESTS
FROM SPANNER_SYS.LOCK_STATS_TOP_MINUTE
ORDER BY LOCK_WAIT_SECONDS DESC
LIMIT 10;

-- 事务统计
SELECT * FROM SPANNER_SYS.TXN_STATS_TOP_10MINUTE
ORDER BY AVG_COMMIT_LATENCY_SECONDS DESC;

-- ============================================================
-- 乐观锁（应用层）
-- ============================================================

CREATE TABLE orders (
    id      INT64 NOT NULL,
    status  STRING(50),
    version INT64 NOT NULL
) PRIMARY KEY (id);

-- 在事务中检查版本
BEGIN TRANSACTION;
    UPDATE orders SET status = 'shipped', version = version + 1
    WHERE id = 100 AND version = 5;
COMMIT;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE 语法（锁是自动管理的）
-- 2. 不支持 LOCK TABLE
-- 3. 不支持 advisory locks
-- 4. 只有两种事务模式：读写 和 只读
-- 5. 读写事务自动获取锁，只读事务使用快照
-- 6. 使用 wound-wait 保证无死锁
-- 7. 事务有超时限制（默认 10 秒）
