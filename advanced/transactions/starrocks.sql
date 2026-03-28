-- StarRocks: 事务
--
-- 参考资料:
--   [1] StarRocks Documentation - Transaction
--       https://docs.starrocks.io/docs/data-operate/transaction

-- ============================================================
-- 1. Import 事务模型 (与 Doris 同源)
-- ============================================================
-- 每个导入任务是一个原子操作。Label 机制保证幂等。
-- 与 Doris 的事务模型完全相同。

-- ============================================================
-- 2. Label 机制
-- ============================================================
INSERT INTO users WITH LABEL insert_20240115
(username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Stream Load: curl -H "label:txn_20240115" ...

-- ============================================================
-- 3. BEGIN/COMMIT
-- ============================================================
BEGIN;
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'a@e.com');
INSERT INTO users (id, username, email) VALUES (2, 'bob', 'b@e.com');
COMMIT;

BEGIN;
INSERT INTO users (id, username, email) VALUES (3, 'charlie', 'c@e.com');
ROLLBACK;

-- ============================================================
-- 4. Pipe 事务 (3.2+，StarRocks 独有)
-- ============================================================
-- CREATE PIPE my_pipe AS INSERT INTO target
-- SELECT * FROM FILES('path'='s3://bucket/data/');
-- 每个文件的加载是一个原子事务。
-- 失败自动重试，成功文件不会重复加载。

-- ============================================================
-- 5. 隔离级别与 MVCC
-- ============================================================
-- 默认 Read Committed。MVCC 快照读。
-- 不支持 Repeatable Read / Serializable。

SHOW TRANSACTION WHERE label = 'txn_20240115';
SHOW LOAD WHERE label = 'insert_20240115';

-- ============================================================
-- 6. StarRocks vs Doris 事务差异
-- ============================================================
-- 核心相同: Import 事务 + Label 幂等 + BEGIN/COMMIT
-- StarRocks 独有: Pipe 持续加载(3.2+)的文件级事务
-- Doris 独有: BEGIN WITH LABEL(带标签事务)
--
-- 对引擎开发者的启示:
--   Pipe 的文件级事务是"持续加载"场景的优雅设计:
--     每个文件独立事务 → 失败不影响其他文件
--     记录已加载文件 → 重启后不重复加载
--   类似 Snowpipe，但集成在引擎内部(无需外部组件)。
