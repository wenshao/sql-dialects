# TiDB: 锁机制

> 参考资料:
> - [TiDB Documentation - Pessimistic Transaction Mode](https://docs.pingcap.com/tidb/stable/pessimistic-transaction)
> - [TiDB Documentation - Optimistic Transaction Mode](https://docs.pingcap.com/tidb/stable/optimistic-transaction)
> - [TiDB Documentation - LOCK STATS / Information Schema TIDB_TRX](https://docs.pingcap.com/tidb/stable/information-schema-tidb-trx)
> - [TiDB Documentation - Deadlock](https://docs.pingcap.com/tidb/stable/information-schema-deadlocks)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 行级锁 (Row-Level Locks) — 悲观模式


TiDB 4.0+ 默认使用悲观事务模式
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;       -- TiDB 6.0+
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;

```

NOWAIT (TiDB 5.0+)
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

```

SKIP LOCKED (TiDB 8.0+)
```sql
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;

```

## 事务模式选择


悲观事务模式（默认，TiDB 4.0+）
```sql
SET GLOBAL tidb_txn_mode = 'pessimistic';
SET SESSION tidb_txn_mode = 'pessimistic';

```

乐观事务模式
```sql
SET SESSION tidb_txn_mode = 'optimistic';
```

乐观模式下写冲突在 COMMIT 时才检测

## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

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

## 死锁检测


TiDB 自动检测死锁
查看死锁历史
```sql
SELECT * FROM information_schema.DEADLOCKS;
```

TiDB 6.1+
```sql
SELECT * FROM information_schema.CLUSTER_DEADLOCKS;

```

锁等待超时
```sql
SET GLOBAL innodb_lock_wait_timeout = 50;

```

## 锁监控


查看当前事务
```sql
SELECT * FROM information_schema.TIDB_TRX;
SELECT * FROM information_schema.CLUSTER_TIDB_TRX;

```

查看数据锁（TiDB 5.3+）
```sql
SELECT * FROM information_schema.DATA_LOCK_WAITS;

```

查看正在运行的查询
```sql
SHOW PROCESSLIST;

```

终止会话
```sql
KILL connection_id;

```

## 事务隔离级别


```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- 默认（快照隔离）
```

TiDB 的 REPEATABLE READ 实际是快照隔离 (SI)
TiDB 不支持 SERIALIZABLE
