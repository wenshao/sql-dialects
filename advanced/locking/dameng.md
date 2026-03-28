# 达梦 (DM): 锁机制 (Locking)

> 参考资料:
> - [达梦数据库 SQL 语言参考 - 锁管理](https://eco.dameng.com/document/dm/zh-cn/sql-dev/sql-lock.html)
> - [达梦数据库 SQL 语言参考 - SELECT FOR UPDATE](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-select.html)
> - [达梦数据库 SQL 语言参考 - 事务管理](https://eco.dameng.com/document/dm/zh-cn/sql-dev/sql-transaction.html)
> - ============================================================
> - 行级锁
> - ============================================================
> - SELECT FOR UPDATE

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
```

## NOWAIT

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
```

## WAIT n（等待指定秒数）

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE WAIT 5;
```

## SKIP LOCKED

```sql
SELECT * FROM tasks WHERE status = 'pending'
  FETCH FIRST 5 ROWS ONLY
FOR UPDATE SKIP LOCKED;
```

## 表级锁


```sql
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN ROW SHARE MODE;
LOCK TABLE orders IN ROW EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;

LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;
```

## MVCC


达梦使用 MVCC 实现并发控制
读不阻塞写，写不阻塞读
隔离级别

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
```

## 乐观锁


```sql
ALTER TABLE orders ADD version INT DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 悲观锁


```sql
BEGIN
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    COMMIT;
END;
```

## 死锁检测


达梦自动检测死锁并回滚其中一个事务
锁超时设置
通过 dm.ini 配置: LOCK_WAIT_TIMEOUT

## 锁监控


## V$LOCK: 查看当前锁

```sql
SELECT * FROM V$LOCK;
```

## 查看锁等待

```sql
SELECT * FROM V$LOCK WHERE BLOCKED = 1;
```

## 查看活跃事务

```sql
SELECT * FROM V$SESSIONS WHERE STATE = 'ACTIVE';
SELECT * FROM V$TRX;
```

## 终止会话

```sql
ALTER SYSTEM KILL SESSION 'sid';
```

## 注意事项


## 兼容 Oracle 的锁语法

## 支持 SELECT FOR UPDATE / NOWAIT / WAIT / SKIP LOCKED

## 支持 LOCK TABLE

## MVCC 实现并发控制

## 与 Oracle 类似，读不阻塞写
