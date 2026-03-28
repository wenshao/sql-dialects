# DB2: 锁机制 (Locking)

> 参考资料:
> - [IBM Db2 Documentation - Locking](https://www.ibm.com/docs/en/db2/11.5?topic=concurrency-locking)
> - [IBM Db2 Documentation - LOCK TABLE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-lock-table)
> - [IBM Db2 Documentation - Isolation Levels](https://www.ibm.com/docs/en/db2/11.5?topic=levels-isolation)
> - [IBM Db2 Documentation - Lock Monitoring](https://www.ibm.com/docs/en/db2/11.5?topic=monitoring-locks)
> - ============================================================
> - 行级锁 (Row-Level Locks)
> - ============================================================
> - SELECT FOR UPDATE（Db2 使用 FOR UPDATE OF 语法）

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
SELECT id, status FROM orders WHERE id = 100 FOR UPDATE OF status;
```

## SELECT FOR READ ONLY（显式声明只读，优化锁获取）

```sql
SELECT * FROM orders WHERE id = 100 FOR READ ONLY;
```

## FOR UPDATE WITH RS/RR（使用指定的隔离级别）

```sql
SELECT * FROM orders WHERE id = 100 FOR READ ONLY WITH RS;
```

## SKIP LOCKED DATA（Db2 9.7+）

```sql
SELECT * FROM tasks WHERE status = 'pending'
FETCH FIRST 5 ROWS ONLY
FOR UPDATE SKIP LOCKED DATA;
```

## 表级锁 (Table-Level Locks)


## LOCK TABLE

```sql
LOCK TABLE orders IN SHARE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
```

## 隔离级别（Db2 特有术语）


Uncommitted Read (UR) = READ UNCOMMITTED
Cursor Stability (CS) = READ COMMITTED（默认）
Read Stability (RS) = REPEATABLE READ
Repeatable Read (RR) = SERIALIZABLE
设置会话隔离级别

```sql
SET CURRENT ISOLATION = CS;
SET CURRENT ISOLATION = RS;
SET CURRENT ISOLATION = RR;
SET CURRENT ISOLATION = UR;
```

## 语句级隔离级别

```sql
SELECT * FROM orders WITH UR;     -- 脏读
SELECT * FROM orders WITH CS;     -- 游标稳定性
SELECT * FROM orders WITH RS;     -- 读稳定性
SELECT * FROM orders WITH RR;     -- 可重复读
```

## 乐观锁


```sql
ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

## 使用 ROW CHANGE TIMESTAMP（Db2 9.5+）

```sql
ALTER TABLE orders ADD COLUMN row_change_ts TIMESTAMP NOT NULL
    GENERATED ALWAYS FOR EACH ROW ON UPDATE AS ROW CHANGE TIMESTAMP;
```

## 使用 ROW CHANGE TOKEN（Db2 特有）

```sql
SELECT id, ROW CHANGE TOKEN FOR orders AS token
FROM orders WHERE id = 100;
```

## 乐观锁定使用 RID_BIT 和 ROW CHANGE TOKEN

```sql
SELECT id, RID_BIT(orders) AS rid, ROW CHANGE TOKEN FOR orders AS token
FROM orders WHERE id = 100;
```

## 悲观锁


## Db2 中的标准悲观锁模式

```sql
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

## 锁超时与死锁


## 锁超时设置

```sql
SET CURRENT LOCK TIMEOUT = 10;        -- 秒
SET CURRENT LOCK TIMEOUT = WAIT 10;
SET CURRENT LOCK TIMEOUT = NOT WAIT;  -- 立即超时
```

数据库级别锁超时
db2 update db cfg for mydb using LOCKTIMEOUT 30
死锁检测间隔
db2 update db cfg for mydb using DLCHKTIME 10000  -- 毫秒
Db2 自动检测死锁，回滚其中一个事务

## 锁监控


## 锁快照

```sql
SELECT * FROM SYSIBMADM.SNAPLOCK;
SELECT * FROM SYSIBMADM.LOCKS_HELD;
```

## MON_GET_LOCKS 表函数（Db2 10.5+）

```sql
SELECT * FROM TABLE(MON_GET_LOCKS(NULL, -1)) AS locks;
```

## 查看锁等待

```sql
SELECT * FROM SYSIBMADM.LOCKWAITS;
```

## MON_GET_APPL_LOCKWAIT 表函数

```sql
SELECT
    lock_object_type,
    lock_mode,
    lock_mode_requested,
    lock_wait_elapsed_time,
    agent_id
FROM TABLE(MON_GET_APPL_LOCKWAIT(NULL, -1)) AS waits;
```

## 锁升级监控

```sql
SELECT
    lock_escals,
    lock_timeouts,
    deadlocks
FROM TABLE(MON_GET_DATABASE(-1)) AS db;
```

## 注意事项


## Db2 支持行级锁、页级锁和表级锁

## 锁可能自动升级（行锁 -> 表锁）

## 使用 LOCKLIST/MAXLOCKS 配置锁内存

## 不支持 advisory locks

## SKIP LOCKED DATA 从 Db2 9.7 开始可用
