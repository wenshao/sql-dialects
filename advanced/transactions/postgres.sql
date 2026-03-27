-- PostgreSQL: 事务
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Transactions
--       https://www.postgresql.org/docs/current/tutorial-transactions.html
--   [2] PostgreSQL Documentation - Transaction Isolation
--       https://www.postgresql.org/docs/current/transaction-iso.html
--   [3] PostgreSQL Documentation - BEGIN
--       https://www.postgresql.org/docs/current/sql-begin.html

-- 基本事务
BEGIN;  -- 或 START TRANSACTION
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END

-- 回滚
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- 保存点
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;  -- 释放保存点
COMMIT;

-- 隔离级别
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- 实际等同于 READ COMMITTED
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- 默认
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;       -- 真正的可串行化（SSI）

-- 会话级别
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET default_transaction_isolation = 'serializable';

-- 查看当前隔离级别
SHOW transaction_isolation;

-- 只读事务
BEGIN TRANSACTION READ ONLY;
SET TRANSACTION READ ONLY;

-- 可延迟事务（9.1+，SERIALIZABLE + READ ONLY）
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
-- 可能等待更久才开始，但执行时不会被串行化失败中断

-- 锁相关
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;  -- 不锁外键引用
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;      -- 只锁主键

-- NOWAIT（8.1+）/ SKIP LOCKED（9.5+）
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- 建议锁（应用层面的锁）
SELECT pg_advisory_lock(12345);         -- 获取
SELECT pg_advisory_unlock(12345);       -- 释放
SELECT pg_try_advisory_lock(12345);     -- 尝试获取（不阻塞）

-- 异常处理（在 PL/pgSQL 中）
-- BEGIN ... EXCEPTION WHEN ... THEN ... END;

-- 注意：PostgreSQL 中 DDL 也是事务性的（可以回滚 CREATE TABLE！）
-- 注意：串行化使用 SSI（Serializable Snapshot Isolation），不是锁
