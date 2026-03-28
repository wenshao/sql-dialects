# YugabyteDB: 锁机制

> 参考资料:
> - [YugabyteDB Documentation - Explicit Row-Level Locking](https://docs.yugabyte.com/latest/explore/transactions/explicit-locking/)
> - [YugabyteDB Documentation - Transaction Isolation Levels](https://docs.yugabyte.com/latest/explore/transactions/isolation-levels/)
> - [YugabyteDB Documentation - Concurrency Control](https://docs.yugabyte.com/latest/architecture/transactions/concurrency-control/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 行级锁（兼容 PostgreSQL）


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;

```

NOWAIT
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

```

SKIP LOCKED
```sql
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;

```

## 表级锁


YugabyteDB 支持 PostgreSQL 风格的 LOCK TABLE
```sql
LOCK TABLE orders IN ACCESS SHARE MODE;
LOCK TABLE orders IN ROW SHARE MODE;
LOCK TABLE orders IN ROW EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

```

## 事务隔离级别


YugabyteDB 支持 Snapshot Isolation 和 Serializable
```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;     -- 快照隔离
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;        -- 默认

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

## 并发控制算法


Wait-on-Conflict: 事务等待冲突事务完成（默认，2.16+）
Fail-on-Conflict: 冲突时立即失败（旧行为）
可通过 yb_enable_read_committed_isolation 配置

## 死锁检测


YugabyteDB 分布式死锁检测
自动检测并终止死锁事务

```sql
SET deadlock_timeout = '1s';
SET lock_timeout = '5s';

```

## 锁监控


```sql
SELECT * FROM pg_locks;

```

查看锁等待
```sql
SELECT pid, pg_blocking_pids(pid), query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

```

终止后端进程
```sql
SELECT pg_terminate_backend(12345);

```

## 注意事项


## 兼容 PostgreSQL 语法

## 分布式架构：锁可能跨节点

## 支持分布式死锁检测

## 默认 SERIALIZABLE 隔离级别

## Wait-on-Conflict 模式减少事务重试

## 不支持 advisory locks（截至 2.x）
