# TDSQL: 锁机制 (Locking)

> 参考资料:
> - [TDSQL 文档 - 分布式事务](https://cloud.tencent.com/document/product/557/7700)
> - [TDSQL 文档 - 锁管理](https://cloud.tencent.com/document/product/557)


## TDSQL 并发模型

TDSQL 是腾讯云分布式数据库（兼容 MySQL）:
1. 支持分布式事务
2. 兼容 MySQL 锁语法
3. 分布式环境下有全局死锁检测

## 行级锁（兼容 MySQL InnoDB）


```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT * FROM orders WHERE id = 100 FOR SHARE;
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;
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

## 分布式事务


## TDSQL 使用两阶段提交（2PC）实现分布式事务

```sql
BEGIN;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- 分片1
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;  -- 分片2
COMMIT;
```

## 全局死锁检测


## TDSQL 在代理层实现全局死锁检测

跨分片的死锁会被自动检测并解决

```sql
SET innodb_lock_wait_timeout = 50;
```

## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 锁监控


## 兼容 MySQL 语法

```sql
SELECT * FROM information_schema.INNODB_TRX;
SHOW ENGINE INNODB STATUS;
```

## 事务隔离级别


```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 默认
```

## 注意事项


## 兼容 MySQL 锁语法

## 分布式事务使用 2PC

## 全局死锁检测

## 跨分片操作有额外开销

## 建议避免长事务和跨分片的大事务
