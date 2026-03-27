-- Apache Doris: 事务
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Doris 的事务支持与传统 RDBMS 不同
-- 主要通过导入任务的原子性来保证数据一致性

-- ============================================================
-- 导入事务（Import Transaction）
-- ============================================================

-- 每个导入任务是一个事务
-- 事务通过 Label 标识，保证幂等性

-- Stream Load（自动事务）
-- curl -H "label:txn_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load
-- 相同 label 的导入不会重复执行

-- INSERT 自带事务
INSERT INTO users WITH LABEL insert_20240115
(username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- ============================================================
-- BEGIN/COMMIT（2.1+，写事务）
-- ============================================================

-- 2.1+ 支持多语句写事务
BEGIN;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users (id, username, email) VALUES (2, 'bob', 'bob@example.com');
COMMIT;

-- 回滚
BEGIN;
INSERT INTO users (id, username, email) VALUES (3, 'charlie', 'charlie@example.com');
ROLLBACK;

-- 带 Label 的事务
BEGIN WITH LABEL txn_20240115;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com');
INSERT INTO orders (id, user_id, amount) VALUES (1, 1, 100.00);
COMMIT;

-- ============================================================
-- 隔离级别
-- ============================================================

-- Doris 默认提供 Read Committed 级别
-- 导入的数据在 COMMIT 后对其他查询可见

-- ============================================================
-- Two-Phase Commit（两阶段提交，2PC）
-- ============================================================

-- Stream Load 支持 2PC
-- 1. Prepare 阶段：curl -H "two_phase_commit:true" ...
-- 2. Commit 阶段：curl -X PUT .../api/db/_commit?txnId=xxx

-- ============================================================
-- 数据一致性保证
-- ============================================================

-- 1. Label 机制保证导入幂等
-- 2. 原子性：一个导入任务要么全部成功，要么全部失败
-- 3. REPLACE/DELETE 操作在 Unique Key 模型上是原子的

-- 查看事务状态
SHOW TRANSACTION WHERE label = 'txn_20240115';

-- 查看导入任务状态
SHOW LOAD WHERE label = 'insert_20240115';

-- ============================================================
-- MVCC（多版本并发控制）
-- ============================================================

-- Doris 使用 MVCC 实现快照读
-- 查询看到的是查询开始时的一致性快照
-- 不受并发导入的影响

-- 注意：Doris 的事务主要面向导入场景
-- 注意：2.1+ 支持 BEGIN/COMMIT 多语句事务
-- 注意：Label 机制保证导入幂等（相同 label 不重复导入）
-- 注意：不支持 SAVEPOINT
-- 注意：不支持传统的行级锁
