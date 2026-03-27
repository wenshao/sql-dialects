-- MySQL: 事务 (InnoDB)
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - InnoDB Transaction Model
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-model.html
--   [2] MySQL 8.0 Reference Manual - InnoDB Multi-Versioning
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html
--   [3] MySQL 8.0 Reference Manual - InnoDB Locking
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html
--   [4] MySQL 8.0 Reference Manual - Consistent Nonlocking Reads
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-consistent-read.html

-- ============================================================
-- 1. 基本事务语法
-- ============================================================
START TRANSACTION;  -- 或 BEGIN (MySQL 中等价)
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 回滚
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- 保存点: 部分回滚
START TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
ROLLBACK TO SAVEPOINT sp1;  -- 只回滚 sp1 之后的操作
COMMIT;                      -- 第一个 UPDATE 仍然生效

-- 自动提交模式
SELECT @@autocommit;          -- 默认 1: 每条 SQL 自动提交
SET autocommit = 0;           -- 关闭: 必须显式 COMMIT

-- 只读事务 (5.6.5+): 优化器可以跳过某些事务开销
START TRANSACTION READ ONLY;

-- ============================================================
-- 2. InnoDB MVCC 的实现（对引擎开发者）
-- ============================================================

-- 2.1 核心概念: Undo Log + Read View
-- MVCC (Multi-Version Concurrency Control) 实现读写不互相阻塞:
--   写操作: 在 undo log 中保存旧版本，修改当前行
--   读操作: 通过 Read View 判断应该看到哪个版本
--
-- 2.2 行版本链 (Version Chain)
-- InnoDB 每行有两个隐藏列:
--   DB_TRX_ID:     最后修改该行的事务 ID
--   DB_ROLL_PTR:   指向 undo log 中上一个版本的指针
-- 修改流程:
--   1. 将当前行拷贝到 undo log (旧版本)
--   2. 修改当前行的数据
--   3. 更新 DB_TRX_ID 为当前事务 ID
--   4. 更新 DB_ROLL_PTR 指向 undo log 中的旧版本
-- 形成版本链: 当前行 → undo_v1 → undo_v2 → ... → 最初版本

-- 2.3 Read View (一致性视图)
-- 事务开始 SELECT 时，InnoDB 创建 Read View，记录:
--   m_ids:        当前所有活跃事务 ID 的列表
--   m_low_limit:  下一个将分配的事务 ID (高水位)
--   m_up_limit:   活跃事务中最小的 ID (低水位)
--   m_creator_id: 创建该 Read View 的事务 ID
--
-- 可见性判定规则（对于行版本的 DB_TRX_ID = trx_id）:
--   if trx_id < m_up_limit:        可见（事务在 Read View 创建前已提交）
--   if trx_id >= m_low_limit:      不可见（事务在 Read View 创建后才开始）
--   if trx_id in m_ids:            不可见（事务在 Read View 创建时仍活跃）
--   else:                          可见（事务在 Read View 创建前已提交）
-- 如果当前版本不可见 → 沿 DB_ROLL_PTR 遍历版本链，找到第一个可见版本

-- 2.4 Undo Log 的清理 (Purge)
-- 旧版本不会立即删除，purge 线程定期清理:
--   当没有任何 Read View 需要看到某个旧版本时，该版本可以被清理
-- 长事务的危害: 持有旧 Read View → 阻止 undo log 清理 → undo 空间膨胀
-- 监控: SELECT * FROM information_schema.INNODB_TRX ORDER BY trx_started;

-- ============================================================
-- 3. 隔离级别: 为什么 REPEATABLE READ 是默认
-- ============================================================

-- MySQL 四种隔离级别:
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 脏读
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- RC
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- RR (默认)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 串行化
SELECT @@transaction_isolation;  -- 查看当前 (8.0+)

-- 3.1 RR vs RC 的 Read View 创建时机
-- REPEATABLE READ:  事务中第一次 SELECT 时创建 Read View，之后复用
--   → 同一事务内多次 SELECT 看到的数据快照一致
-- READ COMMITTED:   每次 SELECT 都重新创建 Read View
--   → 每次 SELECT 都能看到其他事务已提交的最新数据

-- 3.2 为什么 MySQL 选择 RR 而非 RC 作为默认?
-- 历史原因: Statement-Based Replication (SBR)
--   MySQL 早期的主从复制使用 SBR（复制 SQL 语句而非行数据）
--   RC 隔离级别下，不同从库的执行顺序可能不同 → 数据不一致
--   RR + 间隙锁 保证了 SBR 在主从间的一致性
--   8.0 默认 binlog 格式改为 ROW，SBR 的限制已不存在
--   但默认隔离级别保持 RR（向后兼容）
--
-- 3.3 PostgreSQL 为什么选择 RC 作为默认?
--   PG 从第一天就使用行级 MVCC，不存在 SBR 问题
--   RC 的锁范围更小（无间隙锁）→ 并发性能更好
--   PG 的 RR 使用 SSI (Serializable Snapshot Isolation) → 有性能开销
--   生产实践: 绝大多数应用只需要 RC 级别
--
-- 对引擎开发者的启示:
--   1. 默认隔离级别的选择应基于目标场景: OLTP 推荐 RC（更高并发）
--   2. 如果引擎从第一天就用 ROW-based replication，不需要为 SBR 设计锁策略
--   3. 许多 MySQL DBA 在生产环境手动改为 RC 以提高性能

-- ============================================================
-- 4. 间隙锁 (Gap Lock) 和幻读防护
-- ============================================================

-- 4.1 什么是幻读
-- 事务 T1: SELECT * FROM t WHERE age > 20;  -- 返回 3 行
-- 事务 T2: INSERT INTO t VALUES (4, 25);     -- 插入一行 age=25
-- 事务 T2: COMMIT;
-- 事务 T1: SELECT * FROM t WHERE age > 20;  -- 返回 4 行!（幻读）
--
-- RR 级别下，MVCC 的 Read View 可以防止普通 SELECT 的幻读（快照读）
-- 但 SELECT ... FOR UPDATE（当前读）无法靠 Read View 解决

-- 4.2 InnoDB 的间隙锁
-- 间隙锁锁定索引记录之间的 "间隙"，阻止其他事务在间隙中插入新行
-- 三种锁类型:
--   Record Lock:   锁定索引记录本身
--   Gap Lock:      锁定两个索引记录之间的间隙（不含记录本身）
--   Next-Key Lock: Record Lock + Gap Lock（锁记录 + 记录前的间隙）
--
-- 4.3 间隙锁的副作用
-- 间隙锁会降低并发度:
--   场景: WHERE id BETWEEN 10 AND 20 FOR UPDATE
--   锁定范围: (负无穷, 10] [10, 20] (20, 正无穷) 中的间隙
--   其他事务无法在此范围内 INSERT → 可能导致不必要的等待
--
-- 死锁: 间隙锁是 MySQL 死锁的主要来源之一
--   T1: SELECT * FROM t WHERE id = 5 FOR UPDATE;  (id=5 不存在，加间隙锁)
--   T2: SELECT * FROM t WHERE id = 6 FOR UPDATE;  (id=6 不存在，加间隙锁)
--   T1: INSERT INTO t VALUES (5, ...);  -- 等待 T2 的间隙锁
--   T2: INSERT INTO t VALUES (6, ...);  -- 等待 T1 的间隙锁 → 死锁!

-- 4.4 RC 级别下无间隙锁
-- READ COMMITTED 不使用间隙锁（除外键和唯一约束检查）
-- 这是很多团队选择 RC 的重要原因: 减少死锁、提高并发

-- ============================================================
-- 5. 锁语法
-- ============================================================
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;            -- 排他锁
SELECT * FROM accounts WHERE id = 1 FOR SHARE;             -- 共享锁 (8.0+)
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;    -- 旧语法 (仍可用)

-- 8.0+ NOWAIT / SKIP LOCKED
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;     -- 无法获锁立即报错
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED; -- 跳过已锁行

-- SKIP LOCKED 的应用: 任务队列
-- 多个消费者从 tasks 表中获取任务:
--   SELECT * FROM tasks WHERE status='pending' LIMIT 1 FOR UPDATE SKIP LOCKED;
-- 每个消费者获取不同的未锁定行 → 无锁竞争的任务分发

-- ============================================================
-- 6. 横向对比: 各引擎的事务模型（对引擎开发者）
-- ============================================================

-- 6.1 PostgreSQL: Heap-based MVCC
-- 行版本存在堆表中（非 undo log），旧版本由 VACUUM 清理
-- 优势: 回滚 O(1)，读永远不阻塞写
-- 劣势: 表膨胀（dead tuples），需要 autovacuum
-- RR: SSI（Serializable Snapshot Isolation），无间隙锁，用 predicate locks

-- 6.2 Oracle: Undo-based MVCC（InnoDB 的参考模型）
-- 默认 RC。SERIALIZABLE 实际是 Snapshot Isolation（非真正串行化）
-- ORA-01555 "Snapshot too old": undo 被覆盖时的经典错误

-- 6.3 SQL Server: 双模式
-- 悲观并发（默认）+ SNAPSHOT isolation（需启用）
-- RCSI: RC + MVCC（Azure SQL 默认开启），版本存 tempdb

-- 6.4 分布式引擎
-- TiDB: Percolator + TSO  |  CockroachDB: 默认 SERIALIZABLE
-- Spanner: TrueTime 实现外部一致性  |  ClickHouse: 无传统事务

-- 对引擎开发者的启示:
--   1. Undo MVCC (InnoDB/Oracle): 避免表膨胀但回滚慢
--      Heap MVCC (PG): 回滚快但需要 VACUUM
--   2. 间隙锁是 MySQL 特有的幻读方案，代价是死锁; PG 用 SSI 替代
--   3. 分布式事务需要全局时序（TSO/TrueTime/HLC）
--   4. 默认隔离级别: RC 是工业界共识，MySQL 的 RR 默认是历史遗留

-- ============================================================
-- 7. DDL 与事务的关系
-- ============================================================
-- MySQL: DDL 隐式提交当前事务（不能在事务中回滚 DDL）
-- 例:
--   START TRANSACTION;
--   INSERT INTO t VALUES (1);
--   CREATE TABLE t2 (...);   -- 隐式 COMMIT! INSERT 被提交
--   ROLLBACK;                -- 无效，事务已被 DDL 提交
--
-- 横向对比:
--   PostgreSQL: DDL 是事务性的，可以 BEGIN; CREATE TABLE ...; ROLLBACK;
--   SQL Server: DDL 是事务性的
--   Oracle:     DDL 隐式提交（同 MySQL）
--   SQLite:     DDL 是事务性的
--
-- 对引擎开发者的启示:
--   事务性 DDL 是现代数据库的重要能力。
--   MySQL/Oracle 的 DDL 隐式提交使得 schema migration 工具无法在单事务中
--   原子地应用多个 DDL 变更 → 失败时需要手动回滚 → 运维风险

-- ============================================================
-- 8. 版本演进与最佳实践
-- ============================================================
-- MySQL 5.5:   InnoDB 成为默认引擎
-- MySQL 5.6.5: 只读事务 START TRANSACTION READ ONLY
-- MySQL 8.0:   FOR SHARE 替代 LOCK IN SHARE MODE
--              NOWAIT / SKIP LOCKED 支持
--              默认 binlog 格式改为 ROW
-- MySQL 8.0.1: 原子 DDL（单个 DDL 原子性，但仍隐式提交事务）
--
-- 实践建议:
--   1. 事务尽量短 -- 长事务阻止 undo log 清理，导致 ibdata1 膨胀
--   2. 高并发场景考虑 RC 隔离级别（减少间隙锁死锁）
--   3. 使用 SKIP LOCKED 实现高效的任务队列模式
--   4. 监控 INNODB_TRX 和 INNODB_LOCK_WAITS 诊断锁问题
--   5. DDL 操作前确保无重要事务进行中（DDL 会隐式提交）
