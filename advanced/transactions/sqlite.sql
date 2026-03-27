-- SQLite: 事务
--
-- 参考资料:
--   [1] SQLite Documentation - BEGIN TRANSACTION
--       https://www.sqlite.org/lang_transaction.html
--   [2] SQLite Documentation - SAVEPOINT
--       https://www.sqlite.org/lang_savepoint.html
--   [3] SQLite Documentation - WAL Mode
--       https://www.sqlite.org/wal.html

-- 基本事务
BEGIN TRANSACTION;  -- 或 BEGIN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END TRANSACTION

-- 回滚
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- 保存点
SAVEPOINT sp1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
RELEASE SAVEPOINT sp1;    -- 提交保存点
-- 或
ROLLBACK TO SAVEPOINT sp1;  -- 回滚到保存点

-- 事务类型
BEGIN DEFERRED;    -- 默认，延迟获取锁（第一次读/写时获取）
BEGIN IMMEDIATE;   -- 立即获取写锁（防止其他写入）
BEGIN EXCLUSIVE;   -- 立即获取排他锁（防止其他读写）

-- 自动提交：默认每条语句自动提交

-- 隔离级别：SQLite 只有一种
-- 相当于 SERIALIZABLE（通过文件锁实现）

-- WAL 模式（3.7.0+，推荐，允许并发读写）
PRAGMA journal_mode = WAL;
-- WAL 模式下：多个读可以并发，但写仍然互斥

-- 锁相关
-- 没有 SELECT ... FOR UPDATE
-- 并发控制通过文件级锁实现

-- BUSY 超时（等待锁释放的时间）
PRAGMA busy_timeout = 5000;  -- 等待 5 秒

-- 注意：整个数据库只有一把写锁（不是行级或表级锁）
-- 注意：DDL 也是事务性的
-- 注意：不支持行级隔离或行级锁
-- BEGIN CONCURRENT（实验性分支，未合入主线，允许并发写入）
