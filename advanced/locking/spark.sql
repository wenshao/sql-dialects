-- Spark SQL: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Delta Lake Documentation - Concurrency Control
--       https://docs.delta.io/latest/concurrency-control.html
--   [2] Delta Lake Documentation - Optimistic Concurrency
--       https://docs.delta.io/latest/concurrency-control.html#optimistic-concurrency-control
--   [3] Apache Spark Documentation - Spark SQL
--       https://spark.apache.org/docs/latest/sql-ref.html

-- ============================================================
-- Spark SQL 并发模型概述
-- ============================================================
-- Spark SQL 本身没有传统的锁机制:
-- 1. 标准 Spark SQL（Parquet/CSV 等）不支持事务
-- 2. Delta Lake 提供 ACID 事务和乐观并发控制
-- 3. Hive 表通过 Hive Metastore 的锁管理器管理并发
-- 4. 不支持 SELECT FOR UPDATE / FOR SHARE

-- ============================================================
-- Delta Lake 事务（Databricks / OSS Delta Lake）
-- ============================================================

-- Delta Lake 使用乐观并发控制
-- 写操作在提交时检查冲突

-- Delta 表支持 ACID 事务
CREATE TABLE orders (
    id     BIGINT,
    status STRING,
    amount DECIMAL(10,2)
) USING DELTA;

-- INSERT/UPDATE/DELETE/MERGE 都在事务中执行
INSERT INTO orders VALUES (1, 'new', 100.00);

UPDATE orders SET status = 'shipped'
WHERE id = 1;

DELETE FROM orders WHERE status = 'cancelled';

-- MERGE（upsert）
MERGE INTO orders t
USING updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.status = s.status
WHEN NOT MATCHED THEN INSERT *;

-- ============================================================
-- Delta Lake 乐观并发控制
-- ============================================================

-- Delta Lake 写入冲突规则:
-- 1. INSERT 与 INSERT: 不冲突（可并发）
-- 2. INSERT 与 DELETE/UPDATE: 可能冲突（如果涉及相同分区）
-- 3. DELETE/UPDATE 与 DELETE/UPDATE: 如果涉及相同文件则冲突
-- 4. OPTIMIZE 与写入: 可能冲突

-- 冲突时后提交的事务失败，需要重试

-- ============================================================
-- Delta Lake Time Travel（不需要锁）
-- ============================================================

-- 读取历史版本
SELECT * FROM orders VERSION AS OF 5;
SELECT * FROM orders TIMESTAMP AS OF '2024-01-15 10:00:00';

-- 查看表历史
DESCRIBE HISTORY orders;

-- ============================================================
-- Delta Lake 表属性
-- ============================================================

-- 设置隔离级别
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'WriteSerializable'  -- 默认
);

ALTER TABLE orders SET TBLPROPERTIES (
    'delta.isolationLevel' = 'Serializable'       -- 更严格
);

-- ============================================================
-- Hive 表锁（通过 Hive Metastore）
-- ============================================================

-- 如果使用 Hive 表，锁由 Hive Metastore 管理
-- 参见 hive.sql 中的锁机制

SHOW LOCKS;
SHOW LOCKS orders;

-- ============================================================
-- 乐观锁（应用层）
-- ============================================================

-- 使用版本号列
-- Delta Lake 模式
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 标准 Spark SQL 不支持传统锁机制
-- 2. 需要 Delta Lake 或 Apache Iceberg/Hudi 提供 ACID 事务
-- 3. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 4. 不支持 LOCK TABLE
-- 5. Delta Lake 使用乐观并发控制
-- 6. 写入冲突需要应用层重试
-- 7. Time Travel 提供不需要锁的历史数据访问
