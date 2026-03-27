-- ClickHouse: 锁机制 (Locking)
--
-- 参考资料:
--   [1] ClickHouse Documentation - Consistency of Data Parts
--       https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree
--   [2] ClickHouse Documentation - system.mutations
--       https://clickhouse.com/docs/en/operations/system-tables/mutations
--   [3] ClickHouse Documentation - system.processes
--       https://clickhouse.com/docs/en/operations/system-tables/processes

-- ============================================================
-- ClickHouse 并发模型概述
-- ============================================================
-- ClickHouse 是列式分析数据库，设计目标是高吞吐读取:
-- 1. 没有传统的行级锁或事务
-- 2. 写入是追加式的（append-only），通过后台合并处理
-- 3. ALTER/MUTATION 操作异步执行
-- 4. 使用表级别的读写锁保护元数据
-- 5. 不支持 SELECT FOR UPDATE / FOR SHARE

-- ============================================================
-- 表级别的元数据锁
-- ============================================================

-- DDL 操作（ALTER TABLE、DROP TABLE 等）会获取表的排他元数据锁
-- SELECT/INSERT 获取共享元数据锁
-- 这意味着 DDL 操作会等待正在执行的查询完成

-- 查看查询锁等待（ClickHouse 23.3+）
SELECT * FROM system.locks;  -- 如果可用

-- ============================================================
-- Mutation（变更操作）
-- ============================================================

-- ClickHouse 的 UPDATE/DELETE 不是即时操作，而是异步 mutation
ALTER TABLE orders UPDATE status = 'shipped' WHERE id = 100;
ALTER TABLE orders DELETE WHERE status = 'cancelled';

-- Mutation 在后台异步执行，不需要锁定行
-- 查看 mutation 状态
SELECT
    database,
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    latest_fail_reason
FROM system.mutations
WHERE is_done = 0
ORDER BY create_time DESC;

-- 等待 mutation 完成
-- 使用 mutations_sync 设置（1=等待当前副本, 2=等待所有副本）
SET mutations_sync = 1;
ALTER TABLE orders UPDATE status = 'shipped' WHERE id = 100;

-- 取消未完成的 mutation
KILL MUTATION WHERE mutation_id = 'mutation_id_here';

-- ============================================================
-- 乐观并发控制
-- ============================================================

-- 使用 ReplacingMergeTree 引擎实现版本控制
CREATE TABLE orders (
    id       UInt64,
    status   String,
    version  UInt64,
    updated_at DateTime
) ENGINE = ReplacingMergeTree(version)
ORDER BY id;

-- 插入新版本（旧版本在后台合并时被删除）
INSERT INTO orders VALUES (100, 'shipped', 6, now());

-- 强制合并以去除旧版本
OPTIMIZE TABLE orders FINAL;

-- 查询最新版本（合并前可能看到多个版本）
SELECT * FROM orders FINAL WHERE id = 100;

-- ============================================================
-- 插入去重 (Insert Deduplication)
-- ============================================================

-- ReplicatedMergeTree 自动对相同 insert block 去重
-- 这提供了幂等插入的保证

-- 禁用去重
SET insert_deduplicate = 0;

-- ============================================================
-- 分布式锁（ZooKeeper 协调）
-- ============================================================

-- ReplicatedMergeTree 使用 ZooKeeper/ClickHouse Keeper 协调:
-- 1. DDL 操作通过 ZooKeeper 在副本间同步
-- 2. 分布式 DDL 查询使用 ON CLUSTER 子句

ALTER TABLE orders ON CLUSTER my_cluster
    UPDATE status = 'shipped' WHERE id = 100;

-- ============================================================
-- 并发控制设置
-- ============================================================

-- 最大并发查询数
-- max_concurrent_queries = 100（默认）

-- 查看当前运行的查询
SELECT
    query_id,
    user,
    query,
    elapsed,
    read_rows,
    memory_usage
FROM system.processes;

-- 终止查询
KILL QUERY WHERE query_id = 'query_id_here';

-- 设置查询超时
SET max_execution_time = 60;  -- 秒

-- ============================================================
-- 锁监控替代方案
-- ============================================================

-- 查看系统进程
SELECT * FROM system.processes;

-- 查看合并操作
SELECT
    database,
    table,
    elapsed,
    progress,
    num_parts,
    result_part_name
FROM system.merges;

-- 查看分布式 DDL 队列
SELECT * FROM system.distributed_ddl_queue
ORDER BY entry ASC;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. ClickHouse 不支持传统事务 (BEGIN/COMMIT/ROLLBACK)
-- 2. 不支持 SELECT FOR UPDATE / FOR SHARE / LOCK TABLE
-- 3. UPDATE/DELETE 通过 ALTER TABLE ... UPDATE/DELETE 异步执行
-- 4. 适合追加写入场景，不适合频繁的单行更新
-- 5. 使用 ReplacingMergeTree + FINAL 实现更新语义
-- 6. 高并发写入使用 Buffer 引擎或批量插入
