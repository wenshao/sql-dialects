# Teradata: 锁机制 (Locking)

> 参考资料:
> - [Teradata Documentation - Locking](https://docs.teradata.com/r/Teradata-Database-SQL-Request-and-Transaction-Processing/Locking)
> - [Teradata Documentation - LOCKING Modifier](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Manipulation-Language/LOCKING-Modifier)
> - [Teradata Documentation - Lock Logger](https://docs.teradata.com/r/Teradata-Database-Administration/Lock-Logger-Utility)


## LOCKING 修饰符（Teradata 特有）


Teradata 使用 LOCKING 修饰符显式控制锁
```sql
LOCKING TABLE orders FOR ACCESS
SELECT * FROM orders;                     -- 脏读，不获取锁

LOCKING TABLE orders FOR READ
SELECT * FROM orders;                     -- 共享读锁

LOCKING TABLE orders FOR WRITE
SELECT * FROM orders;                     -- 写锁

LOCKING TABLE orders FOR EXCLUSIVE
SELECT * FROM orders;                     -- 排他锁
```


行级锁修饰符
```sql
LOCKING ROW FOR ACCESS
SELECT * FROM orders WHERE id = 100;

LOCKING ROW FOR READ
SELECT * FROM orders WHERE id = 100;

LOCKING ROW FOR WRITE
SELECT * FROM orders WHERE id = 100;
```


数据库级锁
```sql
LOCKING DATABASE mydb FOR READ
SELECT * FROM orders;
```


NOWAIT
```sql
LOCKING TABLE orders FOR WRITE NOWAIT
UPDATE orders SET status = 'shipped' WHERE id = 100;
```


## 锁级别


锁粒度: Database -> Table -> Partition -> Row-hash
Teradata 使用行哈希锁（row-hash lock），不是传统的行锁

ACCESS: 脏读，不阻塞任何操作
READ: 共享锁，阻塞写入
WRITE: 允许读取，阻塞其他写入
EXCLUSIVE: 阻塞所有其他操作（DDL 使用）

## 乐观锁


```sql
ALTER TABLE orders ADD version INTEGER DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```


## 悲观锁


Teradata 中使用 LOCKING 修饰符实现悲观锁
```sql
BEGIN TRANSACTION;
    LOCKING ROW FOR WRITE
    SELECT * FROM accounts WHERE id = 1;

    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
END TRANSACTION;
```


## 死锁处理


Teradata 自动检测死锁并终止其中一个事务
死锁超时默认较短

锁超时（通过 DBS Control 设置）
MaxRowHashLockWait, MaxTableLockWait, MaxDatabaseLockWait

## 锁监控


DBC.LockLogV: 锁日志视图
```sql
SELECT * FROM DBC.LockLogV;
```


DBC.LockInfo: 当前锁信息
```sql
SELECT
    DatabaseName,
    TableName,
    LockType,
    LockStatus,
    UserName
FROM DBC.LOCKINFO;
```


查看等待中的锁
```sql
SELECT * FROM DBC.LOCKINFO WHERE LockStatus = 'WAIT';
```


Lock Logger Utility
启用锁日志: REPLACE LOCK LOGGER ON;
查看锁日志: SELECT * FROM DBC.LockLogV;

## 事务模式


Teradata Transaction (BT/ET)
```sql
BT;  -- BEGIN TRANSACTION
    UPDATE orders SET status = 'shipped' WHERE id = 100;
ET;  -- END TRANSACTION
```


ANSI Transaction mode
```sql
BEGIN TRANSACTION;
    UPDATE orders SET status = 'shipped' WHERE id = 100;
COMMIT;
```


## 注意事项


1. LOCKING 修饰符是 Teradata 特有语法
2. 使用行哈希锁而非真正的行级锁
3. ACCESS 锁允许脏读（类似 SQL Server NOLOCK）
4. 不支持 SELECT FOR UPDATE 语法
5. 不支持 advisory locks
6. 两种事务模式: Teradata (BT/ET) 和 ANSI (BEGIN/COMMIT)
