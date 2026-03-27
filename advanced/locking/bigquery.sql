-- BigQuery: 锁机制 (Locking)
--
-- 参考资料:
--   [1] BigQuery Documentation - Transactions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/transactions
--   [2] BigQuery Documentation - Concurrency Control
--       https://cloud.google.com/bigquery/docs/multi-statement-queries#concurrency
--   [3] BigQuery Documentation - INFORMATION_SCHEMA.JOBS
--       https://cloud.google.com/bigquery/docs/information-schema-jobs

-- ============================================================
-- BigQuery 并发模型概述
-- ============================================================
-- BigQuery 是无服务器分析型数据仓库，与传统 RDBMS 的锁机制不同:
-- 1. 无行级锁或表级锁
-- 2. 使用快照隔离和乐观并发控制
-- 3. DML 操作使用表级别的槽（slot）来串行化写入
-- 4. 多个读取可以并行执行
-- 5. 对同一表的并发 DML 有限制

-- ============================================================
-- 多语句事务（BigQuery 事务支持）
-- ============================================================

-- BigQuery 支持多语句事务（预览版 -> GA）
BEGIN TRANSACTION;
    INSERT INTO mydataset.accounts (id, balance)
    VALUES (1, 1000);

    UPDATE mydataset.accounts
    SET balance = balance - 100
    WHERE id = 1;
COMMIT TRANSACTION;

-- 回滚
BEGIN TRANSACTION;
    UPDATE mydataset.accounts SET balance = balance - 100 WHERE id = 1;
    -- 发现错误
ROLLBACK TRANSACTION;

-- ============================================================
-- 快照隔离 (Snapshot Isolation)
-- ============================================================

-- BigQuery 使用快照隔离:
-- 事务开始时创建数据快照，事务内的所有读取都基于该快照
-- 如果事务提交时发现冲突（其他事务已修改相同数据），则当前事务失败

-- 并发 DML 限制:
-- 同一表的并发 DML 语句受到限制
-- 如果两个事务同时修改同一张表，后提交的事务可能失败

-- ============================================================
-- 乐观并发控制
-- ============================================================

-- BigQuery 内部使用乐观并发控制
-- 写入冲突时后提交的事务会收到错误并需要重试

-- 应用层乐观锁模式
-- 使用版本号或时间戳字段
CREATE TABLE mydataset.orders (
    id         INT64 NOT NULL,
    status     STRING,
    version    INT64 NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

-- 更新时检查版本
BEGIN TRANSACTION;
    -- 读取当前版本
    -- 假设 version = 5
    UPDATE mydataset.orders
    SET status = 'shipped',
        version = version + 1,
        updated_at = CURRENT_TIMESTAMP()
    WHERE id = 100 AND version = 5;

    -- 检查是否更新成功（BigQuery 中需要在应用层验证）
COMMIT TRANSACTION;

-- ============================================================
-- 并发限制与配额
-- ============================================================

-- DML 并发限制:
-- 每个表每天最多 1,500 个 DML 语句（INSERT/UPDATE/DELETE/MERGE）
-- 每 10 秒最多 25 个 DML 操作（对同一表）
-- 并发事务对同一表最多 20 个

-- 查看作业状态（替代锁监控）
SELECT
    job_id,
    user_email,
    state,
    creation_time,
    start_time,
    end_time,
    statement_type,
    total_bytes_processed
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE state = 'RUNNING'
ORDER BY creation_time DESC;

-- 查看特定表的活跃作业
SELECT
    job_id,
    statement_type,
    state,
    creation_time,
    destination_table.table_id
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE destination_table.table_id = 'orders'
  AND state IN ('RUNNING', 'PENDING')
ORDER BY creation_time DESC;

-- ============================================================
-- 替代方案：表复制与原子替换
-- ============================================================

-- 对于需要大批量更新的场景，使用 CTAS + 原子替换
CREATE OR REPLACE TABLE mydataset.orders AS
SELECT
    id,
    CASE WHEN id = 100 THEN 'shipped' ELSE status END AS status,
    version + CASE WHEN id = 100 THEN 1 ELSE 0 END AS version,
    updated_at
FROM mydataset.orders;

-- ============================================================
-- 元数据锁 / Schema 变更
-- ============================================================

-- DDL 操作（ALTER TABLE 等）与 DML 操作是互斥的
-- 如果有正在运行的 DML，DDL 会等待
-- 如果有正在运行的 DDL，DML 会失败

-- 查看表的元数据修改历史
SELECT
    table_name,
    ddl,
    creation_time
FROM mydataset.INFORMATION_SCHEMA.TABLES
WHERE table_name = 'orders';

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. BigQuery 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 没有传统的行级锁或表级锁
-- 3. 并发写入同一表可能导致事务失败
-- 4. 建议使用批量操作减少 DML 次数
-- 5. 对于高并发写入场景，考虑使用流式插入 (streaming insert)
-- 6. 使用 MERGE 语句可以在单个 DML 中完成 upsert 操作
-- 7. 事务隔离级别固定为快照隔离，不可配置
