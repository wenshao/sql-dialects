# openGauss: 锁机制 (Locking)

> 参考资料:
> - [openGauss 文档 - 并发控制](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/LOCK.html)
> - [openGauss 文档 - SELECT FOR UPDATE](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SELECT.html)
> - [openGauss 文档 - pg_locks](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/PG_LOCKS.html)


## 行级锁（基于 PostgreSQL）


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;
```

## NOWAIT / SKIP LOCKED

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;
```

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

## 咨询锁


```sql
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
SELECT pg_try_advisory_lock(12345);
SELECT pg_advisory_xact_lock(12345);
```

## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
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

## 死锁检测


```sql
SHOW deadlock_timeout;
SET deadlock_timeout = '2s';
SET lock_timeout = '5s';
```

## 锁监控


```sql
SELECT * FROM pg_locks;
```

## 查看锁等待

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

SELECT pg_terminate_backend(12345);
```

## 事务隔离级别


```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## 注意事项


## 基于 PostgreSQL 9.2，兼容 PostgreSQL 锁语法

## 支持 advisory locks

## 支持 NOWAIT / SKIP LOCKED

## 华为开源数据库，兼容 PostgreSQL 生态
