# Firebird: 锁机制 (Locking)

> 参考资料:
> - [Firebird Documentation - Concurrency and Locking](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)
> - [Firebird Documentation - Transaction Management](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-transacs)
> - [Firebird Documentation - WITH LOCK](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-dml-select-withlockclause)


## 行级锁


## WITH LOCK（类似 SELECT FOR UPDATE）

```sql
SELECT * FROM orders WHERE id = 100 WITH LOCK;
```

## SKIP LOCKED（Firebird 5.0+）

```sql
SELECT * FROM tasks WHERE status = 'pending'
ROWS 5
WITH LOCK SKIP LOCKED;
```

## 事务与 MVCC


Firebird 使用 MVCC（多版本架构 MGA - Multi-Generational Architecture）
读不阻塞写，写不阻塞读
事务隔离级别

```sql
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;            -- 默认，类似 REPEATABLE READ
SET TRANSACTION ISOLATION LEVEL SNAPSHOT TABLE STABILITY;  -- 类似 SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED RECORD_VERSION;  -- 读取最新提交版本
SET TRANSACTION ISOLATION LEVEL READ COMMITTED NO RECORD_VERSION;
```

## 事务访问模式

```sql
SET TRANSACTION READ ONLY;
SET TRANSACTION READ WRITE;
```

## 事务等待模式

```sql
SET TRANSACTION WAIT;           -- 等待锁（默认）
SET TRANSACTION NO WAIT;        -- 不等待，立即报错
SET TRANSACTION LOCK TIMEOUT 10;  -- 等待最多 10 秒
```

## 表保留（表级别的锁预约）

```sql
SET TRANSACTION
    RESERVING orders FOR SHARED READ,
              accounts FOR PROTECTED WRITE;
```

## 乐观锁


```sql
ALTER TABLE orders ADD version INTEGER DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 悲观锁


```sql
SET TRANSACTION WAIT;
SELECT * FROM accounts WHERE id = 1 WITH LOCK;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
```

## 锁监控


## MON$LOCK_CONFLICT（Firebird 3.0+, 监控表）

```sql
SELECT * FROM MON$ATTACHMENTS;
SELECT * FROM MON$TRANSACTIONS;
SELECT * FROM MON$STATEMENTS;
```

## 查看活跃事务

```sql
SELECT
    MON$ATTACHMENT_ID,
    MON$TRANSACTION_ID,
    MON$STATE,
    MON$TIMESTAMP,
    MON$ISOLATION_MODE
FROM MON$TRANSACTIONS
WHERE MON$STATE = 1;  -- 1 = active
```

## 终止连接

```sql
DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID = 123;
```

## 注意事项


## Firebird 不支持 LOCK TABLE 语句

## 使用 WITH LOCK 代替 FOR UPDATE

## MVCC (MGA) 提供高并发读

## 不支持 advisory locks

## 需要定期 sweep 清理旧版本数据
