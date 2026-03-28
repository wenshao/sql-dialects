# Greenplum: 锁机制 (Locking)

> 参考资料:
> - [Greenplum Documentation - Managing Data](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_mvcc.html)
> - [Greenplum Documentation - LOCK](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-LOCK.html)
> - [Greenplum Documentation - pg_locks](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-system_catalogs-pg_locks.html)


## 行级锁（基于 PostgreSQL）


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;
```


NOWAIT / SKIP LOCKED
```sql
SELECT * FROM orders WHERE status = 'pending' FOR UPDATE NOWAIT;
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;
```


注意: Greenplum 的分布式架构下 FOR UPDATE 有限制
只在追加优化表 (AO) 上有某些限制

## 表级锁


```sql
LOCK TABLE orders IN ACCESS SHARE MODE;
LOCK TABLE orders IN ROW SHARE MODE;
LOCK TABLE orders IN ROW EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE UPDATE EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;
```


## 全局死锁检测


Greenplum 有分布式死锁检测器 (Global Deadlock Detector)
gp_enable_global_deadlock_detector = on（默认 Greenplum 6+）

```sql
SHOW gp_enable_global_deadlock_detector;
```


死锁超时
```sql
SHOW deadlock_timeout;
SET deadlock_timeout = '2s';
```


## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```


## 悲观锁


```sql
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```


## 咨询锁（继承自 PostgreSQL）


```sql
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
SELECT pg_try_advisory_lock(12345);
SELECT pg_advisory_xact_lock(12345);
```


## 锁监控


```sql
SELECT * FROM pg_locks;
```


查看分布式锁等待
```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid
JOIN pg_locks kl ON kl.locktype = bl.locktype
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.pid != bl.pid
JOIN pg_stat_activity blocking ON kl.pid = blocking.pid
WHERE NOT bl.granted;
```


gp_toolkit 扩展
```sql
SELECT * FROM gp_toolkit.gp_locks_on_relation;
```


## 事务隔离级别


```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```


## 注意事项


1. 基于 PostgreSQL，继承大部分锁机制
2. 分布式架构下需要全局死锁检测
3. AO 表 (Append-Optimized) 有不同的锁行为
4. FOR UPDATE 在某些分布式查询中受限
5. 建议使用 LOCK TABLE 而非 SELECT FOR UPDATE 进行表级锁定
