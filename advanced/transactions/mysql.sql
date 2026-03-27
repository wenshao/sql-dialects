-- MySQL: 事务
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - START TRANSACTION
--       https://dev.mysql.com/doc/refman/8.0/en/commit.html
--   [2] MySQL 8.0 Reference Manual - Transaction Isolation Levels
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html
--   [3] MySQL 8.0 Reference Manual - InnoDB Locking
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html

-- 基本事务
START TRANSACTION;  -- 或 BEGIN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 回滚
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- 保存点
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;  -- 只回滚到 sp1
COMMIT;                      -- 第一个 UPDATE 仍然提交

-- 自动提交
SELECT @@autocommit;          -- 默认 1（每条语句自动提交）
SET autocommit = 0;           -- 关闭自动提交

-- 隔离级别
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 脏读
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 不可重复读
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 默认（InnoDB）
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 串行化

-- 全局 / 会话级别
SET GLOBAL TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 查看当前隔离级别
SELECT @@transaction_isolation;  -- 8.0+
SELECT @@tx_isolation;           -- 5.7

-- 只读事务（5.6.5+）
START TRANSACTION READ ONLY;
-- 优化器可以做更多优化

-- 锁相关
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;           -- 排他锁
SELECT * FROM accounts WHERE id = 1 FOR SHARE;            -- 8.0+，共享锁（推荐）
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;   -- 旧语法，共享锁（8.0 仍可用但不推荐）

-- 8.0+: NOWAIT / SKIP LOCKED
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- 注意：MyISAM 不支持事务，只有 InnoDB 支持
-- 注意：DDL 语句（CREATE TABLE、ALTER TABLE 等）会隐式提交事务
