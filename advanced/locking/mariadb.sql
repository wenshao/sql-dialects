-- MariaDB: 锁
-- InnoDB 锁机制与 MySQL 基本一致
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - InnoDB Lock Modes
--       https://mariadb.com/kb/en/innodb-lock-modes/

-- ============================================================
-- 1. 行锁 (InnoDB)
-- ============================================================
-- 共享锁 (S): SELECT ... LOCK IN SHARE MODE (或 FOR SHARE)
SELECT * FROM users WHERE id = 1 LOCK IN SHARE MODE;
SELECT * FROM users WHERE id = 1 FOR SHARE;    -- 10.3+ 语法

-- 排他锁 (X): SELECT ... FOR UPDATE
SELECT * FROM users WHERE id = 1 FOR UPDATE;

-- NOWAIT 和 SKIP LOCKED (10.3+)
SELECT * FROM orders WHERE status = 'pending' FOR UPDATE NOWAIT;
SELECT * FROM orders WHERE status = 'pending' FOR UPDATE SKIP LOCKED;
-- NOWAIT: 不等待锁, 立即报错
-- SKIP LOCKED: 跳过已锁定的行 (用于队列处理)

-- ============================================================
-- 2. 表锁
-- ============================================================
LOCK TABLES users READ, orders WRITE;
-- ... 操作 ...
UNLOCK TABLES;

-- ============================================================
-- 3. 死锁处理
-- ============================================================
-- InnoDB 自动检测死锁并回滚代价最小的事务
-- SHOW ENGINE INNODB STATUS 查看最近的死锁信息
-- innodb_deadlock_detect = ON (默认)
-- 关闭死锁检测 + 使用 innodb_lock_wait_timeout 适用于高并发场景

-- ============================================================
-- 4. 间隙锁 (Gap Lock) 和 Next-Key Lock
-- ============================================================
-- REPEATABLE READ 下, InnoDB 使用 Next-Key Lock 防止幻读:
--   Record Lock: 锁定索引记录
--   Gap Lock: 锁定索引记录之间的间隙
--   Next-Key Lock = Record Lock + Gap Lock
-- 这与 MySQL InnoDB 的行为完全一致

-- ============================================================
-- 5. 对引擎开发者: 锁实现差异
-- ============================================================
-- MariaDB 的 InnoDB 锁管理器与 MySQL 已有微小差异:
--   1. 锁等待超时: 两者默认都是 50 秒 (innodb_lock_wait_timeout)
--   2. 死锁日志: 输出格式可能不同
--   3. 锁调度: 事务优先级和权重计算可能不同
-- SKIP LOCKED 的实现:
--   扫描索引时, 遇到已锁定的行就跳过 (不等待, 不报错)
--   用于实现简单的消息队列: 多个消费者并发取任务
