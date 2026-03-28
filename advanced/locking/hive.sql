-- Hive: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Apache Hive Documentation - Locking
--       https://cwiki.apache.org/confluence/display/Hive/Locking
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- ============================================================
-- 1. 锁模型概述: 两代设计
-- ============================================================
-- Hive 的锁管理经历了两代设计:
--
-- 第一代: ZooKeeper-based Lock Manager (Hive 0.7+)
--   基于 ZooKeeper 实现分布式锁
--   粒度: 表级/分区级（无行级锁）
--   问题: 不支持事务，锁只是并发控制的粗粒度机制
--
-- 第二代: DbTxnManager (Hive 0.13+)
--   基于 Metastore 后端数据库管理锁
--   支持 ACID 事务的行级操作（ORC 格式）
--   Hive 3.0+ 默认使用此管理器

-- ============================================================
-- 2. 配置 ACID 事务锁
-- ============================================================
-- hive-site.xml 配置:
-- hive.support.concurrency = true
-- hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager
-- hive.compactor.initiator.on = true
-- hive.compactor.worker.threads = 4

SET hive.support.concurrency = true;
SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;

-- ============================================================
-- 3. 锁类型与粒度
-- ============================================================
-- SHARED (S):      SELECT 操作获取，允许并发读
-- EXCLUSIVE (X):   INSERT/UPDATE/DELETE/DROP 获取，独占访问
-- SEMI-SHARED:     某些 DDL 操作，允许并发读但阻塞写

-- 锁粒度层级: Database → Table → Partition
-- 非 ACID 表: 只有表级和分区级锁
-- ACID 表:    支持行级操作（通过 delta 文件实现，不是传统行锁）

-- 设计分析: Hive 锁 vs RDBMS 锁
-- Hive 的"行级操作"与 RDBMS 的行级锁有本质区别:
-- RDBMS (MySQL InnoDB): 真正的行级锁，通过锁管理器在内存中维护锁状态
-- Hive ACID: 不是行级锁，而是通过 delta 文件实现行级操作
--   写入时: 变更写入 delta 文件（独立的 ORC 文件），不锁定原始数据
--   读取时: 合并 base 文件 + delta 文件得到最新视图（快照隔离）
--   冲突检测: 在提交时检查是否有冲突（乐观并发控制）

-- ============================================================
-- 4. ACID 表的创建与操作
-- ============================================================
-- Hive 2.x: 需要 ORC + 分桶
CREATE TABLE orders_v2 (
    id     BIGINT,
    status STRING,
    amount DECIMAL(10,2)
)
CLUSTERED BY (id) INTO 8 BUCKETS
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- Hive 3.0+: 不再要求分桶
CREATE TABLE orders_v3 (
    id     BIGINT,
    status STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- ACID 操作
INSERT INTO orders_v3 VALUES (1, 'pending');
UPDATE orders_v3 SET status = 'shipped' WHERE id = 1;
DELETE FROM orders_v3 WHERE id = 1;

-- ============================================================
-- 5. 查看锁与事务
-- ============================================================
SHOW LOCKS;
SHOW LOCKS orders;
SHOW LOCKS orders PARTITION (dt='2024-01-15');
SHOW LOCKS orders EXTENDED;

SHOW TRANSACTIONS;

-- 锁超时配置
SET hive.lock.sleep.between.retries = 60;  -- 重试间隔(秒)
SET hive.lock.numretries = 5;               -- 最大重试次数
SET hive.txn.timeout = 300;                 -- 事务超时(秒)

-- Hive 自动检测死锁并终止其中一个操作

-- ============================================================
-- 6. Compaction: ACID 表的核心维护操作
-- ============================================================
-- ACID 表的写入不修改原始文件，而是创建 delta 文件。
-- 随着 delta 文件增多，读取性能下降（需要合并更多文件）。
-- Compaction 将 delta 文件合并以恢复读取性能。

-- Minor Compaction: 合并多个 delta 文件为一个大 delta
ALTER TABLE orders COMPACT 'minor';

-- Major Compaction: 将 base 文件 + 所有 delta 合并为新的 base
ALTER TABLE orders COMPACT 'major';

-- 分区级 Compaction
ALTER TABLE orders PARTITION (dt='2024-01-15') COMPACT 'major';

-- 查看 Compaction 状态
SHOW COMPACTIONS;

-- 自动 Compaction 配置:
-- hive.compactor.initiator.on = true
-- hive.compactor.worker.threads = 4
-- hive.compactor.delta.num.threshold = 10    -- 触发 minor 的 delta 数量阈值
-- hive.compactor.delta.pct.threshold = 0.1   -- 触发 major 的 delta 占比阈值

-- 设计对比: Hive ACID Compaction vs 其他系统
-- Hive ACID:    delta 文件 + compaction（手动/自动触发）
-- Delta Lake:   类似机制（OPTIMIZE 命令触发 compaction）
-- Iceberg:      expireSnapshots + rewriteDataFiles
-- HBase:        Minor/Major Compaction（类似概念但在 LSM-Tree 上下文）
-- ClickHouse:   MergeTree 后台自动 merge parts

-- ============================================================
-- 7. INSERT OVERWRITE: 非 ACID 表的"锁"替代方案
-- ============================================================
-- 非 ACID 表没有行级锁，但 INSERT OVERWRITE 是原子的:
INSERT OVERWRITE TABLE orders PARTITION (dt='2024-01-15')
SELECT * FROM staging_orders WHERE dt = '2024-01-15';

-- INSERT OVERWRITE 的原子性实现:
-- 1. 写入临时目录
-- 2. 原子性地将临时目录重命名为目标分区目录（HDFS rename 是原子操作）
-- 3. 删除旧的分区目录
-- 这个模式不需要锁就能保证数据一致性（任一时刻读到的都是完整的旧数据或新数据）

-- ============================================================
-- 8. 跨引擎对比: 锁与并发控制
-- ============================================================
-- 引擎           锁粒度       并发控制模型          隔离级别
-- MySQL(InnoDB)  行级锁       MVCC + 2PL           RC/RR/Serializable
-- PostgreSQL     行级锁       MVCC + SSI           RC/RR/Serializable
-- Hive(ACID)     操作级       乐观并发+快照隔离    Snapshot Isolation
-- Hive(非ACID)   分区/表级    INSERT OVERWRITE     无事务
-- BigQuery       无锁         快照隔离(自动)       Snapshot
-- Spark SQL      无锁         Delta Lake MVCC      Serializable(Delta)
-- ClickHouse     无锁         Last-writer-wins     无事务

-- ============================================================
-- 9. 已知限制
-- ============================================================
-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 BEGIN/COMMIT/ROLLBACK 显式事务
-- 3. 每个 SQL 语句是一个隐式事务
-- 4. ACID 需要 ORC 格式（Parquet 不支持）
-- 5. 高并发场景下 Compaction 可能成为瓶颈
-- 6. 锁信息存储在 Metastore 后端数据库中，HMS 是单点

-- ============================================================
-- 10. 对引擎开发者的启示
-- ============================================================
-- 1. Delta 文件 + Compaction 是大数据 ACID 的标准范式:
--    Hive/Delta Lake/Iceberg 都采用了这种 Copy-on-Write 或 Merge-on-Read 模式
-- 2. INSERT OVERWRITE 的原子性来自文件系统 rename:
--    这是一个巧妙的设计——利用文件系统原语实现事务语义
-- 3. 快照隔离是大数据引擎的最佳选择:
--    读不阻塞写、写不阻塞读，代价是需要 compaction
-- 4. 行级锁在分布式环境中代价过高:
--    Hive 的"行级操作"本质上是文件级别的 delta，不是真正的行锁
