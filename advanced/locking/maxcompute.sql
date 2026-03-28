-- MaxCompute (ODPS): 锁机制与并发控制
--
-- 参考资料:
--   [1] MaxCompute 文档 - 并发控制
--       https://help.aliyun.com/zh/maxcompute/user-guide/concurrent-operations
--   [2] MaxCompute 事务表
--       https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables

-- ============================================================
-- 1. MaxCompute 并发模型 —— 分区级乐观并发
-- ============================================================

-- 设计决策: 批处理引擎不需要行级锁
--   OLTP 引擎: 高并发逐行操作 → 需要行级锁保护
--   MaxCompute: 低并发批量操作 → 分区级/表级控制即可
--
--   并发单元: 分区（而非行）
--   并发策略: 乐观并发控制（OCC, Optimistic Concurrency Control）

-- ============================================================
-- 2. 普通表的并发规则
-- ============================================================

-- 规则 1: 同一分区的并发写入 → 串行化（后提交的等待或失败）
--   作业 A: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') SELECT ...;
--   作业 B: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') SELECT ...;
--   结果: 同时提交 → 后提交的等待，超时则失败

-- 规则 2: 不同分区的并发写入 → 并行执行
--   作业 A: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') SELECT ...;
--   作业 B: INSERT OVERWRITE TABLE t PARTITION (dt='20240116') SELECT ...;
--   结果: 完全并行，互不干扰

-- 规则 3: 读写并发 → 快照隔离
--   作业 A: INSERT OVERWRITE TABLE t PARTITION (dt='20240115') SELECT ...;
--   作业 B: SELECT * FROM t WHERE dt = '20240115';
--   结果: 作业 B 读取的是 INSERT OVERWRITE 开始前的快照（不会读到部分结果）

-- INSERT OVERWRITE 的原子性:
--   1. 写入新文件到临时目录
--   2. 原子性替换旧目录（元数据操作）
--   3. 删除旧文件（异步清理）
--   任何步骤失败 → 旧数据不受影响

-- INSERT INTO（追加）的并发:
--   多个 INSERT INTO 同一分区: 每个生成独立的文件，可以并行
--   但可能产生大量小文件 → 需要定期 MERGE SMALLFILES

-- ============================================================
-- 3. 事务表的并发规则
-- ============================================================

CREATE TABLE orders (
    id      BIGINT,
    status  STRING,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

-- 事务表支持更细粒度的并发:
UPDATE orders SET status = 'shipped' WHERE id = 100;
DELETE FROM orders WHERE status = 'cancelled';

-- 事务表的并发控制:
--   基于 MVCC（多版本并发控制）:
--     读操作: 快照隔离（读取事务开始时的数据版本）
--     写操作: 通过 delta 文件实现（不修改 base 文件）
--   冲突检测: 两个事务修改同一行 → 后提交的失败
--   对比 MySQL InnoDB: 也是 MVCC，但粒度是行级锁

-- MERGE 的并发:
MERGE INTO orders t
USING updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.status = s.status
WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.status, s.amount);
-- MERGE 是原子操作: 所有 UPDATE/INSERT 在一个事务中完成

-- ============================================================
-- 4. 不支持的锁机制
-- ============================================================

-- SELECT FOR UPDATE:     不支持（批处理引擎不做悲观锁定）
-- SELECT FOR SHARE:      不支持
-- LOCK TABLE:            不支持（隐式控制）
-- 行级锁:               不支持（粒度太细，开销太大）
-- 表级锁:               隐式（INSERT OVERWRITE 隐式获取分区写锁）
-- 死锁检测:             不需要（乐观并发不持有锁，无死锁可能）

-- ============================================================
-- 5. 应用层乐观锁模式
-- ============================================================

-- 如果需要业务层的乐观并发控制:
ALTER TABLE orders ADD COLUMNS (version BIGINT DEFAULT 0);

-- 更新时检查版本号
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
-- 如果 version != 5（被其他作业修改过）→ 影响 0 行 → 更新失败

-- ============================================================
-- 6. 横向对比: 锁与并发模型
-- ============================================================

-- 并发粒度:
--   MaxCompute: 分区级                 | Hive: 分区级
--   MySQL:      行级（InnoDB MVCC）    | PostgreSQL: 行级（MVCC）
--   BigQuery:   表级（DML 操作）       | Snowflake: 微分区级
--   ClickHouse: 分区级                 | Delta Lake: 文件级

-- 并发策略:
--   MaxCompute: 乐观并发（OCC）        | Hive: 乐观并发
--   MySQL:      悲观锁 + MVCC         | PostgreSQL: 悲观锁 + MVCC
--   BigQuery:   乐观并发              | Snowflake: 乐观并发
--   Delta Lake: OCC + 文件级冲突检测  | Iceberg: OCC + 乐观序列化

-- SELECT FOR UPDATE:
--   MaxCompute: 不支持                | MySQL/PostgreSQL: 支持
--   BigQuery:   不支持                | Snowflake: 不支持

-- 死锁:
--   MaxCompute: 不可能（OCC 无锁持有）| MySQL: 可能（死锁检测+自动回滚）
--   PostgreSQL: 可能（死锁检测）       | BigQuery: 不可能

-- ============================================================
-- 7. 并发最佳实践
-- ============================================================

-- 1. 不同分区并行写入: ETL 管道按分区并行（如多天并行回刷）
-- 2. 避免同一分区的并发写入: DataWorks 调度中设置互斥规则
-- 3. 事务表用于维度表: 需要频繁 UPDATE/DELETE 的小表
-- 4. 普通表用于事实表: 大量追加的日志/交易数据
-- 5. INSERT INTO 注意小文件: 高频追加后定期 MERGE SMALLFILES

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- 1. 分区级并发是大数据引擎最合理的并发粒度 — 行级锁代价太高
-- 2. 乐观并发控制适合低并发批处理 — 无需复杂的锁管理器
-- 3. INSERT OVERWRITE 的原子替换是最安全的写入模式 — 无并发冲突
-- 4. 快照隔离（读取提交前的数据版本）是批处理场景的正确隔离级别
-- 5. 死锁不可能发生是乐观并发的重要优势 — 简化了错误处理
-- 6. Delta Lake/Iceberg 的文件级 OCC 是不可变文件引擎的标准方案
