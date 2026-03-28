# CockroachDB: 锁机制

> 参考资料:
> - [CockroachDB Docs - Transactions](https://www.cockroachlabs.com/docs/stable/transactions.html)
> - [CockroachDB Docs - SELECT FOR UPDATE](https://www.cockroachlabs.com/docs/stable/select-for-update.html)
> - [CockroachDB Docs - Architecture: Transaction Layer](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html)
> - [CockroachDB Docs - SHOW TRANSACTIONS](https://www.cockroachlabs.com/docs/stable/show-transactions.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 行级锁 (Row-Level Locks)


SELECT FOR UPDATE
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

```

SELECT FOR SHARE (CockroachDB 20.2+)
```sql
SELECT * FROM orders WHERE id = 100 FOR SHARE;

```

SELECT FOR NO KEY UPDATE
```sql
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;

```

SELECT FOR KEY SHARE
```sql
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;

```

## NOWAIT / SKIP LOCKED (CockroachDB 20.2+)


```sql
SELECT * FROM orders WHERE status = 'pending'
FOR UPDATE NOWAIT;

SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at
LIMIT 5
FOR UPDATE SKIP LOCKED;

```

## 事务与并发控制


CockroachDB 使用序列化快照隔离 (SSI)
默认且唯一的隔离级别是 SERIALIZABLE
```sql
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

```

设置事务优先级
```sql
BEGIN PRIORITY LOW;
BEGIN PRIORITY NORMAL;
BEGIN PRIORITY HIGH;

```

或在事务内设置
```sql
BEGIN;
SET TRANSACTION PRIORITY HIGH;
```

...
```sql
COMMIT;

```

## 乐观锁与自动重试


CockroachDB 支持自动重试事务（在写-写冲突时）
使用 AS OF SYSTEM TIME 执行历史读取（不需要锁）
```sql
SELECT * FROM orders AS OF SYSTEM TIME '-10s' WHERE id = 100;

```

应用层乐观锁
```sql
ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

```

## 悲观锁


使用 FOR UPDATE 实现悲观锁
```sql
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

```

## 死锁检测


CockroachDB 使用分布式死锁检测
基于事务优先级和时间戳决定哪个事务应被终止
被终止的事务收到 40001 错误代码（serialization failure）

事务超时
```sql
SET statement_timeout = '30s';

```

## 锁监控


查看活跃事务
```sql
SHOW TRANSACTIONS;

```

查看锁等待（CockroachDB 20.2+）
```sql
SELECT * FROM crdb_internal.cluster_locks
WHERE lock_holder IS NOT NULL;

```

查看正在运行的查询
```sql
SHOW QUERIES;

```

取消查询
```sql
CANCEL QUERY 'query_id';

```

取消会话
```sql
CANCEL SESSION 'session_id';

```

查看事务冲突统计
```sql
SELECT * FROM crdb_internal.transaction_contention_events;

```

查看内置监控仪表板
CockroachDB Console -> Metrics -> SQL -> Contention

## 注意事项


## 只支持 SERIALIZABLE 隔离级别

## 不支持 LOCK TABLE

## 不支持 advisory locks

## 写-写冲突会导致事务自动重试或失败

## 分布式事务使用并行提交协议

## 建议使用客户端自动重试逻辑处理序列化错误
