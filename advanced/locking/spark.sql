-- Spark SQL: 锁机制与并发控制 (Locking & Concurrency)
--
-- 参考资料:
--   [1] Delta Lake - Concurrency Control
--       https://docs.delta.io/latest/concurrency-control.html
--   [2] Apache Iceberg - Reliability
--       https://iceberg.apache.org/docs/latest/reliability/

-- ============================================================
-- 1. 核心设计: Spark SQL 没有传统锁机制
-- ============================================================

-- Spark SQL 不支持 SELECT FOR UPDATE、LOCK TABLE、行级锁、页级锁。
-- 这是"计算引擎 vs 数据库引擎"的根本差异:
--   数据库引擎（MySQL/PostgreSQL）: 多用户并发读写同一行，需要锁保证一致性
--   批处理引擎（Spark）: 每次操作读写大量数据，操作粒度是文件/分区，不是行
--
-- Spark SQL 的并发模型分三层:
--   1. 原生 Spark（Parquet/ORC）: 无事务，无锁，写入冲突由文件系统决定
--   2. Delta Lake:               乐观并发控制（OCC），文件级冲突检测
--   3. Hive Metastore:           Metastore 级锁（用于 DDL 操作的协调）
--
-- 对比:
--   MySQL InnoDB: 行级锁 + MVCC（读不阻塞写，写不阻塞读）
--   PostgreSQL:   MVCC + 行级锁 + 表级锁（READ/WRITE/EXCLUSIVE）
--   Oracle:       多版本读一致性 + 行级锁（只有写才加锁）
--   Hive:         Hive 3.0+ ACID（基于文件的 Delta 记录，性能差）
--   Flink SQL:    无锁（流处理，Changelog 语义）
--   ClickHouse:   MergeTree 无锁（LSM-like，合并时处理并发）
--   BigQuery:     快照隔离（每个查询读一致的快照）
--
-- 对引擎开发者的启示:
--   如果你的引擎面向批处理/分析，文件级乐观并发（Delta Lake 模式）是最佳选择。
--   行级锁的实现成本极高（内存管理、死锁检测、锁升级），只有 OLTP 引擎需要。

-- ============================================================
-- 2. Delta Lake: 乐观并发控制（OCC）
-- ============================================================

-- Delta Lake 的事务日志（_delta_log/）是并发控制的基础:
--   每次写入创建一个新的 JSON 提交文件（00000001.json, 00000002.json, ...）
--   提交时检查是否有冲突（乐观锁: 先写再检查，而非先锁再写）

CREATE TABLE orders (
    id     BIGINT,
    status STRING,
    amount DECIMAL(10,2)
) USING DELTA;

-- 每个 DML 操作都是原子事务
INSERT INTO orders VALUES (1, 'new', 100.00);
UPDATE orders SET status = 'shipped' WHERE id = 1;
DELETE FROM orders WHERE status = 'cancelled';

MERGE INTO orders t
USING updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.status = s.status
WHEN NOT MATCHED THEN INSERT *;

-- 冲突规则（哪些并发操作会冲突）:
--   INSERT + INSERT:        不冲突（追加文件，互不影响）
--   INSERT + DELETE/UPDATE: 可能冲突（如果涉及相同的文件）
--   DELETE + DELETE:        如果操作相同文件则冲突
--   OPTIMIZE + 写入:        可能冲突（OPTIMIZE 重写文件）
--
-- 冲突处理: 后提交的事务失败，抛出 ConcurrentModificationException
-- 应用层需要重试: 读取最新版本 -> 重新计算 -> 重新提交

-- ============================================================
-- 3. Delta Lake: 隔离级别
-- ============================================================

-- WriteSerializable（默认）: 写操作串行化，读操作可以并发
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'WriteSerializable'
);

-- Serializable: 更严格，读写都检查冲突
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'Serializable'
);

-- 对比传统数据库隔离级别:
--   Read Uncommitted -> Read Committed -> Repeatable Read -> Serializable
--   Delta Lake 的 WriteSerializable 约等于 Snapshot Isolation
--   Delta Lake 不支持行级的 Repeatable Read（因为没有行级锁）

-- ============================================================
-- 4. Delta Lake: Time Travel（无锁历史访问）
-- ============================================================

-- Time Travel 是 Delta Lake 并发控制的重要补充:
-- 任何时刻的读取都不需要锁——直接读取历史快照

SELECT * FROM orders VERSION AS OF 5;
SELECT * FROM orders TIMESTAMP AS OF '2024-01-15 10:00:00';

DESCRIBE HISTORY orders;

-- RESTORE 回退到历史版本（类似 ROLLBACK 但操作的是版本而非事务）
RESTORE TABLE orders TO VERSION AS OF 5;

-- ============================================================
-- 5. 应用层乐观锁模式
-- ============================================================

-- 版本号列模式（在 Delta Lake 上实现应用级乐观锁）
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 如果 version != 5，说明其他事务已修改，UPDATE 影响 0 行

-- ============================================================
-- 6. Hive Metastore 锁（DDL 操作协调）
-- ============================================================

-- 当使用 Hive Metastore 时，DDL 操作（ALTER TABLE 等）通过 Metastore 锁协调
SHOW LOCKS;
SHOW LOCKS orders;

-- 这不是行级锁，而是表级/分区级的元数据锁
-- 防止两个 Spark 作业同时修改同一张表的 Schema

-- ============================================================
-- 7. Iceberg 的并发控制（对比 Delta Lake）
-- ============================================================

-- Iceberg 也使用乐观并发控制，但实现机制不同:
--   Delta Lake: 事务日志是 JSON 文件序列，通过文件系统原子写入保证一致性
--   Iceberg:    元数据通过 Catalog（如 HMS、REST Catalog）管理，使用 CAS 操作
--
-- Iceberg 的冲突检测更精细:
--   基于 Snapshot 的冲突检测，可以区分"读-写冲突"和"写-写冲突"
--   支持 WAP（Write-Audit-Publish）模式: 先写入 staging 分支，审核后合并到主分支
--
-- SELECT * FROM catalog.db.orders.snapshots;    -- 查看所有快照
-- SELECT * FROM catalog.db.orders.history;      -- 查看历史

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Spark 2.0: 无并发控制（依赖文件系统行为）
-- Delta 0.1: 乐观并发控制（OCC）
-- Delta 1.0: WriteSerializable / Serializable 隔离级别
-- Delta 2.0: 改进冲突检测、行级合并（Deletion Vectors）
-- Iceberg 1.0: 快照隔离、WAP 模式
--
-- 限制:
--   不支持 SELECT FOR UPDATE / FOR SHARE（无行级锁）
--   不支持 LOCK TABLE / UNLOCK TABLE
--   不支持多语句事务（BEGIN/COMMIT/ROLLBACK）——每个 DML 是独立事务
--   并发写入冲突需要应用层重试逻辑
--   Delta Lake / Iceberg 的并发能力远超原生 Spark 表
