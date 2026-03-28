# PolarDB: 锁机制 (Locking)

> 参考资料:
> - [PolarDB for MySQL 文档 - 锁管理](https://help.aliyun.com/document_detail/316770.html)
> - [PolarDB for PostgreSQL 文档 - 锁管理](https://help.aliyun.com/document_detail/472096.html)


## PolarDB 并发模型

PolarDB 有两个版本:
PolarDB for MySQL: 兼容 MySQL 锁机制
PolarDB for PostgreSQL: 兼容 PostgreSQL 锁机制

## PolarDB for MySQL


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
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
LOCK TABLES orders READ;
LOCK TABLES orders WRITE;
UNLOCK TABLES;
```

## 命名锁

```sql
SELECT GET_LOCK('my_lock', 10);
SELECT RELEASE_LOCK('my_lock');
```

## 锁监控

```sql
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;
SELECT * FROM information_schema.INNODB_TRX;
```

## PolarDB for PostgreSQL


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;

SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;
```

## 表级锁

```sql
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE MODE;
```

## 咨询锁

```sql
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
```

## 锁监控

```sql
SELECT * FROM pg_locks;
```

## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 注意事项


## 共享存储架构: 读写分离，只读节点通过物理复制同步

## 锁行为与底层兼容的数据库一致

## 跨节点锁可能有额外延迟

## 读写节点持有锁，只读节点不参与锁管理
