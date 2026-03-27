-- MariaDB: 锁机制 (Locking)
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - InnoDB Lock Modes
--       https://mariadb.com/kb/en/innodb-lock-modes/
--   [2] MariaDB Knowledge Base - LOCK TABLES
--       https://mariadb.com/kb/en/lock-tables/
--   [3] MariaDB Knowledge Base - GET_LOCK
--       https://mariadb.com/kb/en/get_lock/
--   [4] MariaDB Knowledge Base - metadata_lock_info Plugin
--       https://mariadb.com/kb/en/metadata-lock-info/

-- ============================================================
-- 行级锁 (Row-Level Locks) — InnoDB/Aria 引擎
-- ============================================================

-- SELECT FOR UPDATE: 排他行锁
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

-- LOCK IN SHARE MODE（MariaDB 传统语法）
SELECT * FROM orders WHERE id = 100 LOCK IN SHARE MODE;

-- FOR SHARE（MariaDB 10.6+ 兼容 MySQL 8.0 语法）-- 注意：需确认版本支持

-- ============================================================
-- NOWAIT / SKIP LOCKED（MariaDB 10.3+）
-- ============================================================

SELECT * FROM orders WHERE status = 'pending'
FOR UPDATE NOWAIT;

SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at
LIMIT 5
FOR UPDATE SKIP LOCKED;

-- ============================================================
-- Gap Locks / Next-Key Locks (InnoDB)
-- ============================================================

-- 与 MySQL InnoDB 相同的 gap lock 机制
-- REPEATABLE READ 下使用 next-key locking 防止幻读
SELECT * FROM orders WHERE price BETWEEN 10 AND 20 FOR UPDATE;

-- 降级到 READ COMMITTED 可以禁用 gap lock
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- ============================================================
-- 表级锁
-- ============================================================

LOCK TABLES orders READ;
LOCK TABLES orders WRITE;
LOCK TABLES orders READ, users WRITE;
UNLOCK TABLES;

-- FLUSH TABLES WITH READ LOCK（全局读锁，用于备份）
FLUSH TABLES WITH READ LOCK;
-- ... 备份 ...
UNLOCK TABLES;

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INT NOT NULL DEFAULT 1;

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 悲观锁
-- ============================================================

START TRANSACTION;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- ============================================================
-- 应用级锁 (Named Locks)
-- ============================================================

SELECT GET_LOCK('my_lock', 10);
SELECT RELEASE_LOCK('my_lock');
SELECT IS_FREE_LOCK('my_lock');
SELECT IS_USED_LOCK('my_lock');

-- MariaDB 10.0.2+: 支持同时持有多个命名锁
SELECT GET_LOCK('lock_a', 10);
SELECT GET_LOCK('lock_b', 10);
SELECT RELEASE_LOCK('lock_a');
SELECT RELEASE_LOCK('lock_b');
SELECT RELEASE_ALL_LOCKS();

-- ============================================================
-- 死锁检测与预防
-- ============================================================

SHOW ENGINE INNODB STATUS;

SET GLOBAL innodb_lock_wait_timeout = 50;
SET SESSION innodb_lock_wait_timeout = 10;

-- 预防死锁
START TRANSACTION;
    SELECT * FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
COMMIT;

-- ============================================================
-- 锁监控
-- ============================================================

-- information_schema（MariaDB）
SELECT * FROM information_schema.INNODB_LOCKS;
SELECT * FROM information_schema.INNODB_LOCK_WAITS;
SELECT * FROM information_schema.INNODB_TRX;

-- metadata_lock_info 插件（MariaDB 10.0.7+）
INSTALL SONAME 'metadata_lock_info';
SELECT * FROM information_schema.METADATA_LOCK_INFO;

-- ============================================================
-- 事务隔离级别
-- ============================================================

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- 默认
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
