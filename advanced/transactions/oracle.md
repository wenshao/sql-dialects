# Oracle: 事务

> 参考资料:
> - [Oracle SQL Language Reference - COMMIT / ROLLBACK / SAVEPOINT](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/COMMIT.html)
> - [Oracle Database Concepts - Transactions](https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/transactions.html)
> - [Oracle PL/SQL Language Reference - AUTONOMOUS_TRANSACTION](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/AUTONOMOUS_TRANSACTION-pragma.html)

## 基本事务: Oracle 的隐式 BEGIN

Oracle 不需要也不支持显式 BEGIN TRANSACTION
每条 DML 自动开启事务，直到 COMMIT 或 ROLLBACK
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

回滚
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;
```

保存点: 部分回滚
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp_after_debit;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- 发现 id=2 有问题，只回滚第二个操作
ROLLBACK TO SAVEPOINT sp_after_debit;
-- id=1 的扣款仍然生效，可以改为转给 id=3
UPDATE accounts SET balance = balance + 100 WHERE id = 3;
COMMIT;
```

关键区别: DDL 会隐式提交！
  CREATE TABLE ... → 之前未提交的 DML 被自动提交
  ALTER TABLE ...  → 同上
  DROP TABLE ...   → 同上
  这是无数 "数据已经提交了但我没有执行 COMMIT" 问题的根源

## 隔离级别: Oracle 只支持两种

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;   -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

为什么只有两种？
  Oracle 的 MVCC (Multi-Version Concurrency Control) 架构决定了:
  1. READ UNCOMMITTED 没有意义: Oracle 永远不读脏数据，读操作看到的是
     语句开始时的一致性快照（语句级一致性读）
  2. REPEATABLE READ 被 SERIALIZABLE 覆盖: Oracle 的 SERIALIZABLE
     实现的是 Snapshot Isolation，比标准 REPEATABLE READ 更强

Oracle 的 READ COMMITTED vs 其他数据库:
  SQL Server READ COMMITTED: 读取时加 S 锁，读完释放 → 读阻塞写
  Oracle READ COMMITTED:     读取 undo 中的旧版本 → 读不阻塞写，写不阻塞读
  这是 Oracle 并发性能好的根本原因

## 只读事务: 报表一致性

```sql
SET TRANSACTION READ ONLY;
-- 从这一刻起，所有 SELECT 看到的都是事务开始时的快照
-- 即使其他会话在这期间提交了修改，本事务也看不到
SELECT SUM(balance) FROM accounts;           -- 时间点 T1 的数据
SELECT COUNT(*) FROM accounts WHERE balance > 0;  -- 仍然是 T1 的数据
-- 两个查询看到的是完全一致的数据快照
COMMIT;  -- 结束只读事务
```

READ ONLY 事务的用途:
  1. 报表查询: 保证多个查询的数据一致性
  2. 月末对账: 多张表的余额必须匹配
  3. 数据导出: 导出的数据是某一时刻的完整快照

> **注意**: READ ONLY 事务中不能执行 DML，否则报错 ORA-01456
替代: 如果需要在事务中同时读和写，用 SERIALIZABLE

## 自治事务 (Autonomous Transactions)

自治事务独立于主事务，有自己的 COMMIT/ROLLBACK，互不影响
典型用途: 审计日志——即使主事务回滚，日志也必须保留

```sql
CREATE OR REPLACE PROCEDURE log_action(
    p_action  VARCHAR2,
    p_details VARCHAR2
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;         -- 声明为自治事务
BEGIN
    INSERT INTO audit_log (action, details, log_time)
    VALUES (p_action, p_details, SYSTIMESTAMP);
    COMMIT;                                -- 自治事务必须显式 COMMIT 或 ROLLBACK
END;
/
```

使用示例:
```sql
BEGIN
    log_action('TRANSFER', 'Attempting transfer from 1 to 2');
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    -- 如果这里出错回滚，上面的日志仍然保留
    COMMIT;
END;
/
```

自治事务的危险:
  1. 死锁风险: 自治事务试图修改主事务已锁定的行 → 死锁
     主事务等待自治事务完成，自治事务等待主事务释放锁
  2. 数据不一致: 自治事务提交的数据对外可见，但主事务可能回滚
     导致"日志说做了，但实际没做"的情况
  3. 滥用: 有人用自治事务"绕过"事务隔离，这是严重的反模式

正确用法: 只用于日志、审计、序列号生成等"必须持久化"的场景
错误用法: 在自治事务中修改业务数据

## 闪回技术 (Flashback): 时间旅行查询

### 闪回查询 (9i+): 查看过去某时刻的数据

```sql
SELECT * FROM accounts
AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);
```

### 闪回版本查询 (10g+): 查看行的所有版本变更

```sql
SELECT id, balance,
       VERSIONS_STARTTIME,
       VERSIONS_ENDTIME,
       VERSIONS_OPERATION    -- I=Insert, U=Update, D=Delete
FROM accounts
VERSIONS BETWEEN TIMESTAMP
    (SYSTIMESTAMP - INTERVAL '2' HOUR) AND SYSTIMESTAMP
WHERE id = 1;
```

### 闪回事务查询 (10g+): 查看事务级别的变更并生成补偿 SQL

```sql
SELECT xid, operation, undo_sql
FROM flashback_transaction_query
WHERE table_name = 'ACCOUNTS'
  AND commit_scn BETWEEN 123456 AND 234567;
```

### 闪回表 (10g+): 将整个表恢复到过去某个时刻

```sql
ALTER TABLE accounts ENABLE ROW MOVEMENT;  -- 必须先启用
FLASHBACK TABLE accounts TO TIMESTAMP
    (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

> **注意**: 这是 DML 操作（可以回滚），不是从备份恢复

### 闪回数据库 (10g+): 将整个数据库恢复到过去某个时刻

ALTER DATABASE FLASHBACK ON;  -- 需要先启用闪回日志
```sql
FLASHBACK DATABASE TO TIMESTAMP (SYSDATE - 1/24);
```

这需要 DBA 权限，是数据库级别的"后悔药"

闪回技术依赖 UNDO 数据，如果 UNDO 已被覆盖，闪回查询会失败

## ORA-01555 "Snapshot Too Old": 最经典的 Oracle 错误之一

原因: 查询需要的 UNDO 数据已被其他事务覆盖

场景复现:
  1. 会话 A: 执行一个长时间运行的查询（比如 30 分钟的报表）
  2. 会话 B: 频繁更新同一张表并提交
  3. B 的更新产生的新 UNDO 覆盖了 A 需要的旧 UNDO
  4. A 报错: ORA-01555 snapshot too old

解决方案:
  1. 增大 UNDO 表空间 (最直接)
```sql
     ALTER TABLESPACE undotbs1 ADD DATAFILE '/u01/undo02.dbf' SIZE 10G;
```

  2. 增大 UNDO_RETENTION (默认 900 秒)
     ALTER SYSTEM SET UNDO_RETENTION = 3600;  -- 保留 1 小时
> **注意**: UNDO_RETENTION 只是"建议值"，空间不足时 Oracle 仍会覆盖
     GUARANTEE 模式: ALTER TABLESPACE undotbs1 RETENTION GUARANTEE;
     保证不覆盖，但空间不足时 DML 会报错
  3. 优化长查询: 减少查询时间是根本解决办法
  4. SET TRANSACTION READ ONLY: 只读事务让 Oracle 更积极保留 UNDO

## 锁机制详解

行级锁: SELECT FOR UPDATE
```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;          -- 等待直到获得锁
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;   -- 不等待，立即报错
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;   -- 等待最多 5 秒
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED; -- 跳过已锁定的行 (11g+)

-- 锁定特定列（减少锁粒度，但实际上 Oracle 总是行锁）
SELECT * FROM accounts WHERE id = 1 FOR UPDATE OF balance;
```

FOR UPDATE OF col 的主要用途是在多表 JOIN 时指定锁哪张表的行

表级锁
```sql
LOCK TABLE accounts IN EXCLUSIVE MODE;     -- 排他锁: 阻止所有 DML
LOCK TABLE accounts IN SHARE MODE;         -- 共享锁: 允许读，阻止写
LOCK TABLE accounts IN ROW EXCLUSIVE MODE; -- 行排他: DML 自动获取的级别
LOCK TABLE accounts IN SHARE ROW EXCLUSIVE MODE; -- 共享行排他
LOCK TABLE accounts IN EXCLUSIVE MODE NOWAIT;    -- 不等待

-- Oracle 锁的特点:
--   1. 读不阻塞写，写不阻塞读（MVCC 的核心优势）
--   2. 没有锁升级: 100万行更新仍然是行锁，不会升级为表锁
--      （对比 SQL Server: 行锁可能升级为页锁或表锁）
--   3. 死锁自动检测: Oracle 通常在 3 秒内检测到死锁并回滚一个会话
--   4. 只有 DML 加行锁，DDL 加元数据锁 (library cache lock)
```

## 分布式事务

Oracle 原生支持通过 DB Link 的分布式事务
```sql
UPDATE accounts@remote_db SET balance = balance + 100 WHERE id = 1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;  -- 两阶段提交 (2PC)
```

2PC 的问题:
  1. 性能开销: 比本地事务慢很多
  2. In-doubt 事务: 如果协调者在 PREPARE 后崩溃，参与者会挂起
     DBA 需要手动处理: COMMIT FORCE 'transaction_id' 或 ROLLBACK FORCE
  3. 不支持 SERIALIZABLE 隔离级别跨 DB Link

## 查看事务和锁的诊断视图

当前活跃事务
```sql
SELECT * FROM v$transaction;
```

锁等待
```sql
SELECT l1.sid AS blocker, l2.sid AS waiter, l1.type, l1.lmode, l2.request
FROM v$lock l1
JOIN v$lock l2 ON l1.id1 = l2.id1 AND l1.id2 = l2.id2
WHERE l1.block = 1;
```

会话等待事件
```sql
SELECT sid, event, seconds_in_wait, state
FROM v$session_wait
WHERE wait_class != 'Idle';
```

历史等待 (ASH - Active Session History, 10g+)
```sql
SELECT sql_id, event, COUNT(*)
FROM v$active_session_history
WHERE sample_time > SYSDATE - 1/24
GROUP BY sql_id, event
ORDER BY COUNT(*) DESC;
```

## 实用技巧

### COMMIT 的 WRITE 选项 (10gR2+): 控制日志刷新行为

```sql
COMMIT WRITE NOWAIT;           -- 不等待 redo 写入磁盘（更快，但可能丢数据）
COMMIT WRITE WAIT IMMEDIATE;  -- 默认：等待 redo 立即写入磁盘
COMMIT WRITE BATCH;           -- 批量写入 redo（适合高吞吐场景）

-- 2. 使用 DBMS_LOCK.SLEEP 模拟长事务测试
-- EXEC DBMS_SESSION.SLEEP(60);  -- 18c+ 推荐用 DBMS_SESSION.SLEEP

-- 3. 事务名称（用于监控和调试）
SET TRANSACTION NAME 'monthly_billing_run';
```

在 v$transaction.name 中可以看到

注意事项总结:
  1. DDL 隐式提交: 在事务中间执行 DDL 会提交之前的所有修改
  2. 没有 autocommit 设置: Oracle 永远需要显式 COMMIT
     （某些工具如 SQL*Plus 默认 autocommit OFF，但 JDBC 默认 autocommit ON）
  3. Oracle 用 MVCC 实现一致性读: 读不阻塞写，写不阻塞读
  4. 没有 READ UNCOMMITTED: 在 Oracle 中不存在脏读
