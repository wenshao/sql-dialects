# MySQL: 锁机制

> 参考资料:
> - [MySQL 8.0 Reference Manual - InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
> - [MySQL 8.0 Reference Manual - LOCK TABLES](https://dev.mysql.com/doc/refman/8.0/en/lock-tables.html)
> - [MySQL 8.0 Reference Manual - Locking Functions](https://dev.mysql.com/doc/refman/8.0/en/locking-functions.html)
> - [MySQL 8.0 Reference Manual - InnoDB Lock Monitoring](https://dev.mysql.com/doc/refman/8.0/en/innodb-standard-monitor.html)

## 行级锁 (Row-Level Locks) — InnoDB 引擎

SELECT FOR UPDATE: 排他锁
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
```

SELECT FOR SHARE（MySQL 8.0+，替代旧语法 LOCK IN SHARE MODE）
```sql
SELECT * FROM orders WHERE id = 100 FOR SHARE;
```

旧语法（MySQL 5.x 兼容）
```sql
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;
```

## NOWAIT / SKIP LOCKED（MySQL 8.0.1+）

NOWAIT: 无法获取锁时立即报错
```sql
SELECT * FROM orders WHERE status = 'pending'
FOR UPDATE NOWAIT;
```

SKIP LOCKED: 跳过已锁定的行
```sql
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at
LIMIT 5
FOR UPDATE SKIP LOCKED;
```

## Gap Locks / Next-Key Locks（InnoDB 特有）

Gap Lock: 锁定索引记录之间的间隙，防止幻读
在 REPEATABLE READ 隔离级别下自动使用
例如索引值为 10, 20, 30 时，FOR UPDATE 会锁定间隙 (10,20)
```sql
SELECT * FROM orders WHERE price BETWEEN 10 AND 20 FOR UPDATE;
```

此时其他事务无法在 price 10~20 之间插入新记录

Next-Key Lock = Record Lock + Gap Lock
InnoDB 默认在 REPEATABLE READ 级别使用 next-key locking
锁定记录本身 + 记录前面的间隙

Insert Intention Lock: 一种特殊的 gap lock
INSERT 操作在插入前在间隙内设置 insert intention lock

禁用 gap lock（降级到 READ COMMITTED）
```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
```

## 表级锁 (Table-Level Locks)

LOCK TABLES（对所有存储引擎生效）
```sql
LOCK TABLES orders READ;                    -- 共享读锁
LOCK TABLES orders WRITE;                   -- 排他写锁
LOCK TABLES orders READ, users WRITE;       -- 同时锁多张表
UNLOCK TABLES;                              -- 释放所有表锁

-- InnoDB 意向锁（自动获取，不需要手动操作）
-- IS (Intention Shared): 事务打算对行设置共享锁
-- IX (Intention Exclusive): 事务打算对行设置排他锁

-- 元数据锁 (Metadata Lock, MDL)
-- DDL 操作会自动获取 MDL 写锁，DML 获取 MDL 读锁
-- MySQL 5.5+ 自动管理
```

## 乐观锁 (Optimistic Locking)

使用版本号列
```sql
ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

检查 ROW_COUNT() 是否为 1

使用时间戳列
```sql
ALTER TABLE orders ADD COLUMN lock_ts TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6);

UPDATE orders
SET status = 'shipped', lock_ts = CURRENT_TIMESTAMP(6)
WHERE id = 100 AND lock_ts = '2024-01-15 10:30:00.123456';
```

## 悲观锁 (Pessimistic Locking)

```sql
START TRANSACTION;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## 应用级锁 / 命名锁 (Named Locks)

GET_LOCK: 获取命名锁（超时秒数）
```sql
SELECT GET_LOCK('my_lock', 10);           -- 获取锁，等待最多 10 秒
-- 返回 1=成功, 0=超时, NULL=错误

-- RELEASE_LOCK: 释放命名锁
SELECT RELEASE_LOCK('my_lock');           -- 返回 1=成功

-- IS_FREE_LOCK: 检查锁是否空闲
SELECT IS_FREE_LOCK('my_lock');           -- 返回 1=空闲

-- IS_USED_LOCK: 检查锁的持有者
SELECT IS_USED_LOCK('my_lock');           -- 返回连接 ID 或 NULL

-- RELEASE_ALL_LOCKS（MySQL 5.7.5+）
SELECT RELEASE_ALL_LOCKS();
```

## 死锁检测与预防

InnoDB 自动检测死锁，回滚代价最小的事务
查看最近的死锁信息
```sql
SHOW ENGINE INNODB STATUS;
```

innodb_deadlock_detect（MySQL 8.0+）
在高并发场景下可以禁用自动检测，依赖 innodb_lock_wait_timeout
```sql
SET GLOBAL innodb_deadlock_detect = ON;     -- 默认

-- 锁等待超时
SET GLOBAL innodb_lock_wait_timeout = 50;   -- 默认 50 秒
SET SESSION innodb_lock_wait_timeout = 10;
```

预防死锁：按固定顺序获取锁
```sql
START TRANSACTION;
    SELECT * FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
    -- ... 操作 ...
COMMIT;
```

## 锁监控 (Lock Monitoring)

performance_schema 锁表（MySQL 8.0+）
```sql
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;
```

旧版 INFORMATION_SCHEMA（MySQL 5.x，8.0 中已废弃）
```sql
SELECT * FROM information_schema.INNODB_LOCKS;
SELECT * FROM information_schema.INNODB_LOCK_WAITS;
SELECT * FROM information_schema.INNODB_TRX;
```

查看当前锁等待
```sql
SELECT
    r.trx_id              AS waiting_trx_id,
    r.trx_mysql_thread_id AS waiting_thread,
    r.trx_query           AS waiting_query,
    b.trx_id              AS blocking_trx_id,
    b.trx_mysql_thread_id AS blocking_thread,
    b.trx_query           AS blocking_query
FROM information_schema.INNODB_TRX r
JOIN performance_schema.data_lock_waits w
    ON r.trx_id = w.REQUESTING_ENGINE_TRANSACTION_ID
JOIN information_schema.INNODB_TRX b
    ON b.trx_id = w.BLOCKING_ENGINE_TRANSACTION_ID;
```

查看元数据锁
```sql
SELECT * FROM performance_schema.metadata_locks;
```

## 事务隔离级别与 MVCC

InnoDB 使用 MVCC 实现非锁定读
```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

SERIALIZABLE 级别下所有 SELECT 自动转为 SELECT ... FOR SHARE
