# SAP HANA: 锁机制 (Locking)

> 参考资料:
> - [SAP HANA SQL Reference - Transaction Management](https://help.sap.com/docs/HANA_SERVICE_CF/7c78579ce9b14a669c1f3295b0d8ca16/20fdf9cb75191014b85aaa9dec841291.html)
> - [SAP HANA Administration - Lock Handling](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/20ae0ee0751910149561f03db6435cca.html)
> - [SAP HANA SQL Reference - SELECT FOR UPDATE](https://help.sap.com/docs/HANA_SERVICE_CF/7c78579ce9b14a669c1f3295b0d8ca16/20fcf24075191014a89e9dc7b8408b26.html)
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

## WAIT n（SAP HANA 2.0 SPS 04+）

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE WAIT 10;
```

## 表级锁


## LOCK TABLE（SAP HANA）

```sql
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN SHARE MODE;
```

## NOWAIT

```sql
LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;
```

## MVCC 与快照隔离


SAP HANA 使用 MVCC 实现快照隔离
行存表和列存表都支持 MVCC
隔离级别

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;       -- 默认
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

## 乐观锁


```sql
ALTER TABLE orders ADD (version INTEGER DEFAULT 1 NOT NULL);

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 悲观锁


```sql
SET AUTOCOMMIT OFF;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## 死锁检测


## SAP HANA 自动检测死锁

锁等待超时

```sql
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM')
    SET ('transaction', 'lock_wait_timeout') = '30000000';  -- 微秒
```

## 锁监控


## M_LOCK_WAITS_STATISTICS 系统视图

```sql
SELECT * FROM SYS.M_LOCK_WAITS_STATISTICS;
```

## 查看当前事务锁

```sql
SELECT
    LOCK_OWNER_TRANSACTION_ID,
    LOCK_OWNER_CONNECTION_ID,
    ACQUIRED_LOCK_TYPE,
    OBJECT_NAME,
    RECORD_ID
FROM SYS.M_OBJECT_LOCKS;
```

## 查看锁等待

```sql
SELECT
    BLOCKED_TRANSACTION_ID,
    BLOCKED_CONNECTION_ID,
    LOCK_OWNER_TRANSACTION_ID,
    LOCK_TYPE,
    OBJECT_NAME
FROM SYS.M_BLOCKED_TRANSACTIONS;
```

## 查看活跃事务

```sql
SELECT * FROM SYS.M_TRANSACTIONS WHERE CONNECTION_ID != 0;
```

## 终止会话

```sql
ALTER SYSTEM CANCEL SESSION 'connection_id';
ALTER SYSTEM DISCONNECT SESSION 'connection_id';
```

## 意向锁 (Intent Locks)


SAP HANA 自动管理意向锁:
IS (Intent Shared): 表明事务打算读取某些行
IX (Intent Exclusive): 表明事务打算修改某些行

## Record Lock vs Table Lock


行存表: 使用行级锁
列存表: 使用行级锁或范围锁
DDL: 使用表级排他锁

## 注意事项


## 支持 SELECT FOR UPDATE / FOR UPDATE NOWAIT

## 支持 LOCK TABLE

## 不支持 FOR SHARE / LOCK IN SHARE MODE

## 不支持 advisory locks

## MVCC 提供高并发读

## 列存表和行存表的锁行为略有不同
