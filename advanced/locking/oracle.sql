-- Oracle: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Oracle Database Concepts - Data Concurrency and Consistency
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/data-concurrency-and-consistency.html
--   [2] Oracle SQL Language Reference - SELECT FOR UPDATE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [3] Oracle PL/SQL Packages - DBMS_LOCK
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_LOCK.html
--   [4] Oracle Database Reference - V$LOCK
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/refrn/V-LOCK.html

-- ============================================================
-- 行级锁 (Row-Level Locks)
-- ============================================================

-- SELECT FOR UPDATE: 排他行锁
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

-- 锁定特定列（Oracle 特有）
SELECT * FROM orders WHERE id = 100 FOR UPDATE OF orders.status;

-- NOWAIT: 无法获取锁时立即报错
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

-- WAIT n: 等待指定秒数后超时
SELECT * FROM orders WHERE id = 100 FOR UPDATE WAIT 5;

-- SKIP LOCKED（Oracle 11g+）
SELECT * FROM tasks WHERE status = 'pending'
  AND ROWNUM <= 5
FOR UPDATE SKIP LOCKED;

-- 注意：Oracle 没有 SELECT FOR SHARE（读不阻塞写，MVCC 设计）

-- ============================================================
-- 表级锁 (Table-Level Locks)
-- ============================================================

-- LOCK TABLE 语句
LOCK TABLE orders IN ROW SHARE MODE;             -- RS (= SS)
LOCK TABLE orders IN ROW EXCLUSIVE MODE;          -- RX (= SX)
LOCK TABLE orders IN SHARE MODE;                  -- S
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;    -- SRX (= SSX)
LOCK TABLE orders IN EXCLUSIVE MODE;              -- X

-- NOWAIT
LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;

-- WAIT n
LOCK TABLE orders IN EXCLUSIVE MODE WAIT 10;

-- ============================================================
-- 乐观锁 (Optimistic Locking)
-- ============================================================

-- 使用版本号列
ALTER TABLE orders ADD version NUMBER DEFAULT 1 NOT NULL;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 检查 SQL%ROWCOUNT 是否为 1

-- 使用 ORA_ROWSCN（Oracle 特有的行变更 SCN）
SELECT id, ORA_ROWSCN FROM orders WHERE id = 100;
-- 更新时检查 ORA_ROWSCN 是否变化
UPDATE orders SET status = 'shipped'
WHERE id = 100 AND ORA_ROWSCN = 123456789;
-- 注意：默认 ORA_ROWSCN 精度为块级，需要 ROWDEPENDENCIES 表选项才能行级

-- 创建支持行级 ORA_ROWSCN 的表
CREATE TABLE orders_v2 (
    id     NUMBER PRIMARY KEY,
    status VARCHAR2(20)
) ROWDEPENDENCIES;

-- ============================================================
-- 悲观锁 (Pessimistic Locking)
-- ============================================================

-- 典型悲观锁模式
BEGIN
    SELECT * INTO v_account FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- ============================================================
-- 应用锁 / 用户锁 (DBMS_LOCK)
-- ============================================================

-- 分配锁句柄
DECLARE
    v_lockhandle VARCHAR2(128);
    v_result     NUMBER;
BEGIN
    -- 将锁名称转换为句柄
    DBMS_LOCK.ALLOCATE_UNIQUE('my_lock', v_lockhandle);

    -- 请求锁
    v_result := DBMS_LOCK.REQUEST(
        lockhandle        => v_lockhandle,
        lockmode          => DBMS_LOCK.X_MODE,    -- 排他模式
        timeout           => 10,                   -- 超时秒数
        release_on_commit => TRUE                  -- 提交时释放
    );
    -- v_result: 0=成功, 1=超时, 2=死锁, 3=参数错误, 4=已持有, 5=非法句柄

    -- ... 执行需要互斥的操作 ...

    -- 释放锁
    v_result := DBMS_LOCK.RELEASE(v_lockhandle);
END;
/

-- 锁模式:
-- DBMS_LOCK.SS_MODE (2) = Sub-Shared
-- DBMS_LOCK.SX_MODE (3) = Sub-Exclusive
-- DBMS_LOCK.S_MODE  (4) = Shared
-- DBMS_LOCK.SSX_MODE(5) = Shared-Sub-Exclusive
-- DBMS_LOCK.X_MODE  (6) = Exclusive

-- ============================================================
-- 死锁检测与预防
-- ============================================================

-- Oracle 自动检测死锁（通常在 3 秒内），回滚其中一个事务的语句
-- ORA-00060: deadlock detected while waiting for resource

-- 设置 DDL 锁超时（Oracle 11g+）
ALTER SESSION SET DDL_LOCK_TIMEOUT = 10;   -- 秒

-- 预防死锁：按固定顺序锁定行
SELECT * FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;

-- 查看死锁跟踪文件
-- 死锁信息自动写入 alert log 和 trace 文件

-- ============================================================
-- 锁监控 (Lock Monitoring)
-- ============================================================

-- V$LOCK: 查看当前所有锁
SELECT * FROM V$LOCK WHERE TYPE IN ('TX', 'TM');

-- 查看锁等待
SELECT
    s1.username       AS blocking_user,
    s1.sid            AS blocking_sid,
    s2.username       AS waiting_user,
    s2.sid            AS waiting_sid,
    s2.event          AS wait_event,
    s2.seconds_in_wait
FROM V$SESSION s1
JOIN V$SESSION s2 ON s1.sid = s2.blocking_session
WHERE s2.blocking_session IS NOT NULL;

-- DBA_BLOCKERS / DBA_WAITERS
SELECT * FROM DBA_BLOCKERS;
SELECT * FROM DBA_WAITERS;

-- V$LOCKED_OBJECT: 查看被锁定的对象
SELECT
    lo.session_id,
    lo.oracle_username,
    o.object_name,
    o.object_type,
    lo.locked_mode
FROM V$LOCKED_OBJECT lo
JOIN DBA_OBJECTS o ON lo.object_id = o.object_id;

-- 终止阻塞会话
ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE;

-- ============================================================
-- MVCC 与事务隔离
-- ============================================================

-- Oracle 使用 MVCC (Undo Segments) 实现一致性读
-- 读操作永远不阻塞写操作（不需要 FOR SHARE）

-- 隔离级别（Oracle 只支持两种）
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 只读事务
SET TRANSACTION READ ONLY;

-- 使用 AS OF (闪回查询) 实现历史数据读取
SELECT * FROM orders AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '5' MINUTE
WHERE id = 100;

SELECT * FROM orders AS OF SCN 123456789;
