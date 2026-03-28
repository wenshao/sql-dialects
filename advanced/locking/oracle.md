# Oracle: 锁机制

> 参考资料:
> - [Oracle Database Concepts - Data Concurrency and Consistency](https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/data-concurrency-and-consistency.html)
> - [Oracle SQL Language Reference - SELECT FOR UPDATE](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html)

## Oracle 锁设计哲学: 读不阻塞写

Oracle MVCC 的核心原则:
  1. 读操作永远不阻塞写操作
  2. 写操作永远不阻塞读操作
  3. 只有写-写冲突需要等待

因此 Oracle 没有 SELECT FOR SHARE（不需要!）
读一致性通过 Undo 段实现（MVCC），不需要读锁。

横向对比:
  Oracle:     读不阻塞写（MVCC via Undo），无 FOR SHARE
  PostgreSQL: 读不阻塞写（MVCC），有 FOR SHARE
  MySQL/InnoDB: 读不阻塞写（MVCC），有 FOR SHARE (8.0+)
  SQL Server: 默认读阻塞写!（除非 READ_COMMITTED_SNAPSHOT ON）

## 行级锁: SELECT FOR UPDATE

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;
```

锁定特定列（Oracle 独有，指定哪个表的行被锁定）
```sql
SELECT * FROM orders o JOIN users u ON o.user_id = u.id
WHERE o.id = 100
FOR UPDATE OF o.status;                        -- 只锁定 orders 表的行

-- NOWAIT: 无法获取锁时立即报错
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;
```

WAIT n: 等待指定秒数后超时
```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE WAIT 5;
```

SKIP LOCKED（11g+，队列处理的关键特性）
```sql
SELECT * FROM tasks WHERE status = 'pending'
AND ROWNUM <= 5 FOR UPDATE SKIP LOCKED;
```

设计分析: SKIP LOCKED
  SKIP LOCKED 跳过已被其他事务锁定的行，返回下一批可用行。
  典型场景: 多消费者队列（每个消费者取不同的任务）。

横向对比:
  Oracle 11g+:    FOR UPDATE SKIP LOCKED
  PostgreSQL 9.5+: FOR UPDATE SKIP LOCKED
  MySQL 8.0+:     FOR UPDATE SKIP LOCKED
  SQL Server:     READPAST Hint

## 表级锁

```sql
LOCK TABLE orders IN ROW SHARE MODE;           -- RS
LOCK TABLE orders IN ROW EXCLUSIVE MODE;        -- RX
LOCK TABLE orders IN SHARE MODE;                -- S
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;  -- SRX
LOCK TABLE orders IN EXCLUSIVE MODE;            -- X

LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;
LOCK TABLE orders IN EXCLUSIVE MODE WAIT 10;
```

## 乐观锁（推荐的并发控制方式）

方式 1: 版本号
```sql
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

SQL%ROWCOUNT = 0 表示乐观锁冲突

方式 2: ORA_ROWSCN（Oracle 独有的行级变更 SCN）
```sql
SELECT id, ORA_ROWSCN FROM orders WHERE id = 100;
UPDATE orders SET status = 'shipped'
WHERE id = 100 AND ORA_ROWSCN = 123456789;
```

ORA_ROWSCN 的设计:
  默认精度为块级（同一个数据块的所有行共享 SCN）
  要获得行级精度: CREATE TABLE t (...) ROWDEPENDENCIES;
  这是 MVCC 的副产品: SCN 本来就是事务管理的一部分

## 应用锁 / 用户锁（DBMS_LOCK）

```sql
DECLARE
    v_lockhandle VARCHAR2(128);
    v_result     NUMBER;
BEGIN
    DBMS_LOCK.ALLOCATE_UNIQUE('my_lock', v_lockhandle);
    v_result := DBMS_LOCK.REQUEST(
        lockhandle        => v_lockhandle,
        lockmode          => DBMS_LOCK.X_MODE,
        timeout           => 10,
        release_on_commit => TRUE
    );
    -- 0=成功, 1=超时, 2=死锁, 4=已持有
    -- ... 互斥操作 ...
    v_result := DBMS_LOCK.RELEASE(v_lockhandle);
END;
/
```

横向对比:
  Oracle:     DBMS_LOCK（应用锁包，功能丰富）
  PostgreSQL: pg_advisory_lock()（轻量级，更易用）
  MySQL:      GET_LOCK() / RELEASE_LOCK()
  SQL Server: sp_getapplock / sp_releaseapplock

## 死锁检测

Oracle 自动检测死锁（通常 3 秒内），回滚其中一个事务的当前语句
ORA-00060: deadlock detected while waiting for resource

预防死锁: 按固定顺序锁定行
```sql
SELECT * FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
```

DDL 锁超时（11g+）
```sql
ALTER SESSION SET DDL_LOCK_TIMEOUT = 10;
```

## 锁监控

V$LOCK: 当前所有锁
```sql
SELECT * FROM V$LOCK WHERE TYPE IN ('TX', 'TM');
```

查看锁等待（谁阻塞了谁）
```sql
SELECT
    s1.username AS blocking_user, s1.sid AS blocking_sid,
    s2.username AS waiting_user, s2.sid AS waiting_sid,
    s2.seconds_in_wait
FROM V$SESSION s1
JOIN V$SESSION s2 ON s1.sid = s2.blocking_session
WHERE s2.blocking_session IS NOT NULL;
```

DBA_BLOCKERS / DBA_WAITERS（便捷视图）
```sql
SELECT * FROM DBA_BLOCKERS;
SELECT * FROM DBA_WAITERS;
```

终止阻塞会话
```sql
ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE;
```

## 事务隔离级别

Oracle 只支持两种隔离级别:
```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

只读事务
```sql
SET TRANSACTION READ ONLY;
```

横向对比:
  Oracle:     只有 READ COMMITTED 和 SERIALIZABLE
  PostgreSQL: READ UNCOMMITTED(=RC) / RC / REPEATABLE READ / SERIALIZABLE
  MySQL:      所有 4 种标准隔离级别
  SQL Server: 所有 4 种 + SNAPSHOT

Oracle 没有脏读（READ UNCOMMITTED）:
这是 MVCC 的自然结果: 未提交的数据在 Undo 中，读操作看到的是已提交的版本。

## Flashback Query（历史数据读取，基于 MVCC）

```sql
SELECT * FROM orders AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '5' MINUTE
WHERE id = 100;

SELECT * FROM orders AS OF SCN 123456789;
```

Flashback 是 MVCC Undo 段的高价值复用（见 DELETE 文件的详细分析）

## 对引擎开发者的总结

1. "读不阻塞写"是 Oracle MVCC 的核心优势，通过 Undo 段实现。
2. FOR UPDATE OF 指定锁定哪个表的行，在 JOIN 场景下更精确。
3. SKIP LOCKED 是队列处理的关键特性，所有现代数据库已跟进。
4. ORA_ROWSCN 是 MVCC 的副产品，提供了优雅的乐观锁实现。
5. Oracle 只有 2 种隔离级别（RC + SERIALIZABLE），设计哲学是"简化选择"。
6. V$SESSION 和 V$LOCK 是生产环境锁诊断的核心视图。
