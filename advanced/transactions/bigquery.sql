-- BigQuery: 事务
--
-- 参考资料:
--   [1] BigQuery - Multi-Statement Transactions
--       https://cloud.google.com/bigquery/docs/multi-statement-queries#transactions
--   [2] BigQuery SQL Reference - DML Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- BigQuery 支持多语句事务（Multi-statement Transactions）

-- ============================================================
-- 基本事务
-- ============================================================

BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT TRANSACTION;

-- 回滚
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK TRANSACTION;

-- ============================================================
-- 脚本中的事务
-- ============================================================

BEGIN
    BEGIN TRANSACTION;

    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;

    IF (SELECT balance FROM accounts WHERE id = 1) < 0 THEN
        ROLLBACK TRANSACTION;
        RAISE USING MESSAGE = 'Insufficient balance';
    END IF;

    COMMIT TRANSACTION;

EXCEPTION WHEN ERROR THEN
    ROLLBACK TRANSACTION;
    RAISE USING MESSAGE = @@error.message;
END;

-- ============================================================
-- 事务隔离级别
-- ============================================================

-- BigQuery 使用快照隔离（Snapshot Isolation）
-- 所有事务自动使用快照隔离，不可更改
-- 事务开始时看到一致的数据快照

-- ============================================================
-- DML 事务特性
-- ============================================================

-- 单个 DML 语句是原子的
UPDATE users SET status = 0 WHERE last_login < '2023-01-01';
-- 这个 UPDATE 要么完全成功，要么完全失败

-- 多个 DML 可以在事务中组合
BEGIN TRANSACTION;
INSERT INTO orders VALUES (1, 100, '2024-01-15');
INSERT INTO order_items VALUES (1, 1, 50.00);
INSERT INTO order_items VALUES (1, 2, 50.00);
COMMIT TRANSACTION;

-- ============================================================
-- 并发控制
-- ============================================================

-- BigQuery 自动处理并发冲突
-- 同一行的并发修改使用乐观并发控制
-- 冲突时后提交的事务会失败

-- 表级别的并发限制：
-- 每个表每秒最多 5 个 DML 语句
-- 使用 MERGE 代替多个 INSERT/UPDATE 可以减少 DML 数量

-- ============================================================
-- MERGE（原子的 UPSERT）
-- ============================================================

-- MERGE 在一个事务中完成插入或更新
MERGE INTO users AS target
USING staging_users AS source
ON target.id = source.id
WHEN MATCHED THEN
    UPDATE SET username = source.username, email = source.email
WHEN NOT MATCHED THEN
    INSERT (id, username, email) VALUES (source.id, source.username, source.email);

-- ============================================================
-- 临时表在事务中的使用
-- ============================================================

-- 使用临时表暂存中间结果
CREATE TEMP TABLE staging AS
SELECT * FROM raw_data WHERE quality_check = 'pass';

BEGIN TRANSACTION;
DELETE FROM final_data WHERE batch_id = @current_batch;
INSERT INTO final_data SELECT * FROM staging;
COMMIT TRANSACTION;

-- 注意：BigQuery 事务使用快照隔离
-- 注意：每个表每秒最多 5 个 DML 语句
-- 注意：单个事务的超时时间为 10 分钟
-- 注意：DDL 语句不能包含在事务中
-- 注意：SELECT 不需要事务（自动快照一致性）
