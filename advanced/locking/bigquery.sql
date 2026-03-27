-- BigQuery: 锁机制（Locking）
--
-- 参考资料:
--   [1] BigQuery Documentation - Concurrency Control
--       https://cloud.google.com/bigquery/docs/multi-statement-queries#concurrency
--   [2] BigQuery Documentation - DML Concurrency
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- ============================================================
-- 1. BigQuery 的并发模型（对引擎开发者）
-- ============================================================

-- BigQuery 没有传统意义上的锁（行锁、表锁、意向锁）。
-- 它使用乐观并发控制（Optimistic Concurrency Control, OCC）:
--
-- (a) SELECT: 完全无锁
--     任意数量的 SELECT 可以并发执行，互不影响。
--     每个 SELECT 读取提交时的数据快照。
--
-- (b) DML: 表级乐观锁
--     多个 DML 可以同时开始执行。
--     COMMIT 时检查冲突: 如果两个 DML 修改了同一个表的同一个分区，
--     后提交的 DML 失败（需要应用层重试）。
--
-- (c) DDL: 元数据锁
--     DDL 修改表结构时获取元数据锁。
--     DDL 执行期间该表的 DML 等待。
--
-- 为什么选择乐观并发控制?
-- BigQuery 的 DML 并发度很低（配额限制每表 ~5 个并发 DML）。
-- 在低并发环境中，OCC 比悲观锁更高效:
--   悲观锁: 每次操作都获取锁 → 锁管理开销
--   OCC:    只在提交时检查冲突 → 大部分操作无额外开销

-- ============================================================
-- 2. DML 并发行为
-- ============================================================

-- 2.1 同一表的多个 DML
-- 配额: 每个表最多约 5 个并发 DML
-- 超出配额: 排队等待（不是立即失败）
--
-- 冲突场景:
-- 事务 A: UPDATE t SET x = 1 WHERE date = '2024-01-15'
-- 事务 B: DELETE FROM t WHERE date = '2024-01-15'
-- → 修改同一分区 → 后提交的失败

-- 2.2 不同表的 DML: 完全并行，无冲突

-- 2.3 SELECT + DML: SELECT 不被 DML 阻塞
-- 查询读取 DML 开始前的快照（快照隔离）

-- ============================================================
-- 3. 事务中的锁行为
-- ============================================================

-- 多语句事务持有快照:
-- BEGIN TRANSACTION;
-- SELECT * FROM t;              -- 快照时间点
-- UPDATE t SET x = 1 WHERE ...;  -- 基于快照检查冲突
-- COMMIT TRANSACTION;            -- 提交时验证无冲突
--
-- 事务最长持续 6 小时。
-- 长事务增加冲突概率（快照越旧，其他 DML 修改同一分区的概率越高）。

-- ============================================================
-- 4. 查看并发状态
-- ============================================================

-- 查看正在运行的作业
SELECT job_id, user_email, state, query, creation_time
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE state = 'RUNNING';

-- 查看最近的 DML 操作
SELECT job_id, statement_type, total_bytes_processed,
       dml_statistics.inserted_row_count,
       dml_statistics.updated_row_count,
       dml_statistics.deleted_row_count
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE statement_type IN ('INSERT', 'UPDATE', 'DELETE', 'MERGE')
ORDER BY creation_time DESC LIMIT 20;

-- 取消正在运行的作业
-- bq cancel job_id

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 的并发设计:
--   (1) SELECT 完全无锁 → 分析查询不受 DML 影响
--   (2) DML 乐观并发 → 低并发环境最高效
--   (3) 分区级冲突检测 → 不同分区的 DML 不冲突
--   (4) 无行级锁 → 简化实现但不适合 OLTP
--
-- 对比:
--   MySQL:      行级锁 + MVCC（高并发 OLTP）
--   PostgreSQL: 行级锁 + MVCC（高并发 OLTP）
--   SQLite:     文件级锁 + WAL（嵌入式）
--   ClickHouse: 几乎无锁（不可变 part）
--   BigQuery:   乐观并发（低并发云数仓）
--
-- 对引擎开发者的启示:
--   锁设计应该匹配目标并发度:
--   - OLTP（数千并发）: 行级锁 + MVCC
--   - 嵌入式（10 以下并发）: 文件级锁 + WAL
--   - 云数仓（5 以下 DML 并发）: 乐观并发控制
--   - OLAP 追加写入: 不可变存储 → 无需锁
