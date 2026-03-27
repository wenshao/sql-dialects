-- Oracle: 事务
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - COMMIT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/COMMIT.html
--   [2] Oracle SQL Language Reference - ROLLBACK
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ROLLBACK.html
--   [3] Oracle SQL Language Reference - SET TRANSACTION
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SET-TRANSACTION.html

-- Oracle 不需要显式 BEGIN（DML 自动开启事务）
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 回滚
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- 保存点
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- 隔离级别（只支持两种）
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;   -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 只读事务
SET TRANSACTION READ ONLY;
-- 看到的是事务开始时的快照，整个事务期间数据一致

-- 查看事务信息
SELECT * FROM v$transaction;

-- 锁相关
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;   -- 不等待
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;   -- 等待 5 秒
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED; -- 11g+

-- 锁定特定列（减少锁范围）
SELECT * FROM accounts WHERE id = 1 FOR UPDATE OF balance;

-- 手动锁表
LOCK TABLE accounts IN EXCLUSIVE MODE;
LOCK TABLE accounts IN SHARE MODE;

-- 自治事务（独立提交，不影响主事务）
-- 在 PL/SQL 中使用 PRAGMA AUTONOMOUS_TRANSACTION

-- 闪回事务（10g+）
-- SELECT * FROM accounts AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);

-- 注意：DDL 语句会隐式提交当前事务
-- 注意：没有显式的 BEGIN TRANSACTION
-- 注意：Oracle 使用多版本并发控制（MVCC），读不阻塞写
-- 注意：没有 READ UNCOMMITTED 和 REPEATABLE READ 隔离级别
