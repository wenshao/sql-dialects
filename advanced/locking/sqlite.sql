-- SQLite: 锁机制（Locking）
--
-- 参考资料:
--   [1] SQLite Documentation - File Locking and Concurrency
--       https://www.sqlite.org/lockingv3.html
--   [2] SQLite Documentation - WAL Mode
--       https://www.sqlite.org/wal.html

-- ============================================================
-- 1. SQLite 的 5 级文件锁（对引擎开发者最重要的部分）
-- ============================================================

-- SQLite 使用文件级锁（不是行级锁或表级锁），有 5 个状态:
--
-- UNLOCKED → SHARED → RESERVED → PENDING → EXCLUSIVE
--
-- (1) UNLOCKED: 无锁，未读写
-- (2) SHARED:   读锁，允许多个连接同时持有
--     → SELECT 语句获取 SHARED 锁
-- (3) RESERVED:  预写锁，整个数据库最多一个
--     → 第一个写操作获取 RESERVED 锁
--     → 其他连接仍可获取 SHARED 锁（读不被阻塞）
-- (4) PENDING:   即将写入，阻止新的 SHARED 锁
--     → 等待所有现有 SHARED 锁释放
-- (5) EXCLUSIVE:  独占锁，正在写入磁盘
--     → 所有其他连接被阻塞（包括读）
--
-- 设计分析:
--   为什么是文件级锁而非行级锁?
--   (a) SQLite 是嵌入式数据库，没有独立的锁管理器进程
--   (b) 文件锁依赖操作系统（fcntl/flock），零额外开销
--   (c) 嵌入式场景通常并发度低（单个应用内的线程竞争）
--
-- 对比:
--   MySQL InnoDB: 行级锁 + 间隙锁 + MVCC（高并发 OLTP）
--   PostgreSQL:   行级锁 + MVCC（高并发 OLTP）
--   ClickHouse:   无锁（追加写入，不可变 part）
--   BigQuery:     表级乐观锁（低并发批量操作）

-- ============================================================
-- 2. 事务类型对锁的影响
-- ============================================================

-- 默认事务（DEFERRED）: 延迟获取锁
BEGIN;                          -- 不立即获取锁
SELECT * FROM users;            -- 获取 SHARED 锁
UPDATE users SET age = 26;      -- 升级到 RESERVED → EXCLUSIVE
COMMIT;                         -- 释放所有锁

-- IMMEDIATE 事务: 立即获取 RESERVED 锁
BEGIN IMMEDIATE;                -- 立即获取 RESERVED 锁
-- → 其他连接可以读但不能写
-- → 避免了 DEFERRED 模式下的锁升级死锁

-- EXCLUSIVE 事务: 立即获取 EXCLUSIVE 锁
BEGIN EXCLUSIVE;                -- 立即获取 EXCLUSIVE 锁
-- → 其他连接既不能读也不能写
-- → 最安全但并发性最差

-- 死锁场景（DEFERRED 模式）:
--   连接 A: BEGIN; SELECT... (SHARED)
--   连接 B: BEGIN; SELECT... (SHARED)
--   连接 A: UPDATE... → 需要 EXCLUSIVE，等待 B 释放 SHARED
--   连接 B: UPDATE... → 需要 EXCLUSIVE，等待 A 释放 SHARED
--   → 死锁! SQLite 会返回 SQLITE_BUSY 错误
--
-- 解决: 使用 BEGIN IMMEDIATE 避免锁升级死锁

-- ============================================================
-- 3. WAL 模式: 并发性能的关键突破
-- ============================================================

PRAGMA journal_mode = WAL;

-- WAL (Write-Ahead Logging) 模式改变了锁的行为:
--
-- Rollback Journal（默认）:
--   写入前备份旧页 → 修改原始数据 → 提交时删除 journal
--   → 读写互斥（EXCLUSIVE 锁阻塞所有读）
--
-- WAL:
--   写入追加到 WAL 文件 → 读操作读原始数据（不受影响）
--   → 读写并发（读不被写阻塞，写不被读阻塞）
--   → 但仍然是单写（同时只有一个写连接）
--
-- WAL 模式的限制:
--   (a) 仍然是单写（不是多写并发）
--   (b) 需要共享内存文件（-shm），不支持 NFS/CIFS 网络文件系统
--   (c) WAL 文件增长需要 checkpoint（WAL → 主数据库文件）
--   (d) 大量写入可能导致 WAL 文件很大

-- 自动 checkpoint
PRAGMA wal_autocheckpoint = 1000;  -- 每 1000 页自动 checkpoint
-- 手动 checkpoint
PRAGMA wal_checkpoint(TRUNCATE);   -- checkpoint 并截断 WAL 文件

-- ============================================================
-- 4. SQLITE_BUSY 处理
-- ============================================================

-- 当锁冲突时，SQLite 返回 SQLITE_BUSY 错误（不是等待）。
-- 这与 MySQL（等待 innodb_lock_wait_timeout 秒）的行为不同。

-- 设置 busy timeout（等待而非立即报错）
PRAGMA busy_timeout = 5000;       -- 等待最多 5 秒

-- busy_handler 回调（C API，更精细的控制）
-- sqlite3_busy_handler(db, callback, user_data);
-- 回调函数决定是重试还是放弃

-- ============================================================
-- 5. 锁模式（PRAGMA locking_mode）
-- ============================================================

PRAGMA locking_mode = NORMAL;      -- 默认: 事务结束释放锁
PRAGMA locking_mode = EXCLUSIVE;   -- 整个连接期间持有 EXCLUSIVE 锁

-- EXCLUSIVE locking_mode 的用途:
--   (a) 性能: 不需要重复获取/释放锁（减少系统调用）
--   (b) 安全: 防止其他进程同时访问数据库
--   (c) 长时间批量操作: 避免被其他连接中断

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 锁模型的核心设计:
--   (1) 文件级锁 → 简单但并发度低
--   (2) 5 级锁状态 → 精细的读写协调
--   (3) WAL 模式 → 读写并发但仍单写
--   (4) SQLITE_BUSY → 立即返回而非等待（与 OLTP 不同）
--
-- 对引擎开发者的启示:
--   嵌入式数据库的锁设计应优先考虑:
--   (a) 简单性: 文件锁比行级锁实现简单几个数量级
--   (b) 读写分离: WAL 是嵌入式引擎并发的标准解决方案
--   (c) 避免死锁: BEGIN IMMEDIATE 比检测死锁更实用
--   (d) 超时控制: busy_timeout 比无限等待更适合嵌入式场景
