-- SQLite: 锁机制 (Locking)
--
-- 参考资料:
--   [1] SQLite Documentation - File Locking and Concurrency
--       https://www.sqlite.org/lockingv3.html
--   [2] SQLite Documentation - WAL Mode
--       https://www.sqlite.org/wal.html
--   [3] SQLite Documentation - BEGIN TRANSACTION
--       https://www.sqlite.org/lang_transaction.html
--   [4] SQLite Documentation - PRAGMA locking_mode
--       https://www.sqlite.org/pragma.html#pragma_locking_mode

-- ============================================================
-- SQLite 锁模型概述
-- ============================================================
-- SQLite 使用数据库级别的锁（不是行级或表级锁）
-- 锁状态：UNLOCKED -> SHARED -> RESERVED -> PENDING -> EXCLUSIVE
--
-- UNLOCKED:  无锁
-- SHARED:    可以读，多个连接可同时持有
-- RESERVED:  准备写入，只能有一个，不阻止新的 SHARED
-- PENDING:   等待所有 SHARED 释放，阻止新的 SHARED
-- EXCLUSIVE: 可以写入，独占数据库

-- ============================================================
-- 事务类型（控制锁获取时机）
-- ============================================================

-- DEFERRED（默认）: 延迟获取锁，第一次读获取 SHARED，第一次写获取 RESERVED
BEGIN DEFERRED TRANSACTION;
    SELECT * FROM orders;       -- 获取 SHARED 锁
    UPDATE orders SET status = 'done' WHERE id = 1;  -- 升级为 RESERVED
COMMIT;                         -- 升级为 EXCLUSIVE 并写入

-- IMMEDIATE: 立即获取 RESERVED 锁，阻止其他写入
BEGIN IMMEDIATE TRANSACTION;
    -- 已获取 RESERVED 锁，保证后续写操作不会因锁冲突失败
    UPDATE orders SET status = 'done' WHERE id = 1;
COMMIT;

-- EXCLUSIVE: 立即获取 EXCLUSIVE 锁，阻止所有其他连接读写
BEGIN EXCLUSIVE TRANSACTION;
    -- 独占数据库
    UPDATE orders SET status = 'done' WHERE id = 1;
    INSERT INTO logs (msg) VALUES ('order updated');
COMMIT;

-- ============================================================
-- WAL 模式 (Write-Ahead Logging)
-- ============================================================
-- WAL 模式下允许读写并发：读不阻塞写，写不阻塞读

-- 启用 WAL 模式
PRAGMA journal_mode = WAL;

-- WAL 模式的特点:
-- 1. 多个读取可以与一个写入同时进行
-- 2. 写入仍然是串行的（同一时间只能有一个写入者）
-- 3. 更好的并发性能

-- WAL 检查点（将 WAL 文件的内容写回主数据库文件）
PRAGMA wal_checkpoint;
PRAGMA wal_checkpoint(FULL);
PRAGMA wal_checkpoint(TRUNCATE);

-- 自动检查点阈值（WAL 文件页数）
PRAGMA wal_autocheckpoint = 1000;   -- 默认 1000 页

-- ============================================================
-- 锁超时 (Busy Timeout)
-- ============================================================

-- 设置等待锁的超时时间（毫秒）
PRAGMA busy_timeout = 5000;         -- 等待 5 秒

-- 默认 busy_timeout = 0（立即返回 SQLITE_BUSY）

-- 在 C API 中可以设置自定义 busy handler
-- sqlite3_busy_handler() / sqlite3_busy_timeout()

-- ============================================================
-- 乐观锁 (Optimistic Locking)
-- ============================================================

-- 使用版本号列
ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 检查 changes() 返回值

-- 使用 data_version PRAGMA（检测数据库是否被其他连接修改）
PRAGMA data_version;
-- 如果返回值在两次调用之间发生变化，说明数据库已被修改

-- ============================================================
-- 悲观锁 (Pessimistic Locking)
-- ============================================================

-- SQLite 没有行级悲观锁，使用 IMMEDIATE/EXCLUSIVE 事务代替
BEGIN IMMEDIATE;
    SELECT * FROM accounts WHERE id = 1;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 锁模式 (Locking Mode)
-- ============================================================

-- NORMAL（默认）: 每个事务结束后释放锁
PRAGMA locking_mode = NORMAL;

-- EXCLUSIVE: 持有锁直到连接关闭（减少锁获取/释放开销）
PRAGMA locking_mode = EXCLUSIVE;

-- ============================================================
-- 死锁处理
-- ============================================================

-- SQLite 不会产生传统的死锁（因为是数据库级别锁）
-- 但 DEFERRED 事务可能导致活锁（两个事务都持有 SHARED 并尝试升级为 RESERVED）
-- 解决方案：使用 BEGIN IMMEDIATE 代替 BEGIN DEFERRED

-- SQLITE_BUSY 错误处理
-- 当无法获取锁时返回 SQLITE_BUSY (error code 5)
-- 应用层应该重试事务

-- ============================================================
-- 监控
-- ============================================================

-- SQLite 没有系统表来查看锁状态
-- 使用 C API: sqlite3_db_status() 获取运行时状态

-- 编译时可以启用锁跟踪
-- SQLITE_ENABLE_LOCK_TRACE 预处理宏

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. SQLite 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 没有行级锁或表级锁，只有数据库级别锁
-- 3. 同一时间只能有一个写入者
-- 4. WAL 模式是提高并发的最佳方式
-- 5. 对于高并发场景，建议使用 BEGIN IMMEDIATE
-- 6. 网络文件系统 (NFS) 上的锁不可靠
