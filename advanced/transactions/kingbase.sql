-- KingbaseES (人大金仓): 事务
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 基本事务
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

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
RELEASE SAVEPOINT sp1;
COMMIT;

-- 隔离级别
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 会话级别
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 查看当前隔离级别
SHOW transaction_isolation;

-- 只读事务
BEGIN TRANSACTION READ ONLY;

-- 锁相关
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;

-- NOWAIT / SKIP LOCKED
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;

-- 建议锁
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
SELECT pg_try_advisory_lock(12345);

-- 注意事项：
-- 事务语法与 PostgreSQL 完全兼容
-- DDL 也是事务性的（可以回滚）
-- 支持建议锁（Advisory Lock）
-- 使用 SSI（Serializable Snapshot Isolation）实现串行化
