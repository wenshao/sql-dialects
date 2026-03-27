-- Greenplum: 事务
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- Greenplum 基于 PostgreSQL，支持完整的事务功能

-- ============================================================
-- 基本事务
-- ============================================================

BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 回滚
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- ============================================================
-- 保存点
-- ============================================================

BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- ============================================================
-- 隔离级别
-- ============================================================

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- 默认
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;       -- 可串行化

-- 会话级别
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET default_transaction_isolation = 'serializable';

-- 查看当前隔离级别
SHOW transaction_isolation;

-- 注意：Greenplum 不支持 REPEATABLE READ（等同于 SERIALIZABLE）

-- ============================================================
-- 只读事务
-- ============================================================

BEGIN TRANSACTION READ ONLY;
SELECT * FROM users;
COMMIT;

SET TRANSACTION READ ONLY;

-- ============================================================
-- 锁
-- ============================================================

-- 行级锁
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;

-- 表级锁
LOCK TABLE users IN ACCESS EXCLUSIVE MODE;
LOCK TABLE users IN SHARE MODE;

-- 建议锁
SELECT pg_advisory_lock(12345);
SELECT pg_advisory_unlock(12345);
SELECT pg_try_advisory_lock(12345);

-- ============================================================
-- 分布式事务
-- ============================================================

-- Greenplum 使用 2PC（两阶段提交）保证分布式一致性
-- Master 协调所有 Segment 的事务
-- 这对用户是透明的

-- ============================================================
-- 异常处理（PL/pgSQL）
-- ============================================================

-- BEGIN ... EXCEPTION WHEN ... THEN ... END;

-- ============================================================
-- 死锁检测
-- ============================================================

-- 设置死锁检测超时
SET deadlock_timeout = '1s';

-- 查看锁信息
SELECT * FROM pg_locks WHERE NOT granted;

-- 注意：Greenplum 兼容 PostgreSQL 事务语法
-- 注意：DDL 也是事务性的（可以回滚 CREATE TABLE）
-- 注意：分布式事务由 Master 协调，对用户透明
-- 注意：不支持 REPEATABLE READ 隔离级别
-- 注意：大事务可能影响分布式性能
