-- Snowflake: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Snowflake Documentation - Transactions
--       https://docs.snowflake.com/en/sql-reference/transactions
--   [2] Snowflake Documentation - Understanding Lock Behavior
--       https://docs.snowflake.com/en/sql-reference/transactions#label-transactions-locking-resources
--   [3] Snowflake Documentation - LOCK_TIMEOUT
--       https://docs.snowflake.com/en/sql-reference/parameters#lock-timeout
--   [4] Snowflake Documentation - SHOW LOCKS
--       https://docs.snowflake.com/en/sql-reference/sql/show-locks

-- ============================================================
-- Snowflake 并发模型概述
-- ============================================================
-- Snowflake 使用基于 MVCC 的快照隔离:
-- 1. 读操作不加锁，使用事务开始时的快照
-- 2. DML 操作（INSERT/UPDATE/DELETE/MERGE）获取表级锁（对微分区）
-- 3. DDL 操作获取表级排他锁
-- 4. 不支持行级锁
-- 5. 不支持 SELECT FOR UPDATE / FOR SHARE

-- ============================================================
-- 事务
-- ============================================================

-- 手动事务
BEGIN TRANSACTION;
    INSERT INTO orders (id, status) VALUES (1, 'new');
    UPDATE orders SET status = 'confirmed' WHERE id = 1;
COMMIT;

-- 自动提交（默认行为）
-- 每个 DML 语句都是独立的事务
ALTER SESSION SET AUTOCOMMIT = TRUE;   -- 默认

-- 禁用自动提交
ALTER SESSION SET AUTOCOMMIT = FALSE;
-- 之后需要手动 COMMIT 或 ROLLBACK

-- ============================================================
-- 表级别锁（自动获取）
-- ============================================================

-- Snowflake 自动管理锁:
-- DML 操作: 获取表的写锁（允许并发读）
-- DDL 操作: 获取表的排他锁（阻塞所有其他操作）
-- SELECT: 不获取锁（使用 MVCC 快照）

-- 查看当前锁
SHOW LOCKS;

-- 查看特定账户的锁
SHOW LOCKS IN ACCOUNT;

-- ============================================================
-- 锁超时
-- ============================================================

-- 设置锁等待超时（秒）
ALTER SESSION SET LOCK_TIMEOUT = 43200;   -- 默认 43200 秒（12 小时）
ALTER SESSION SET LOCK_TIMEOUT = 60;      -- 设置为 1 分钟

-- 语句级超时
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 172800;  -- 默认 48 小时

-- ============================================================
-- 乐观并发控制
-- ============================================================

-- Snowflake 内部使用乐观并发控制
-- 如果两个并发事务修改相同的微分区，后提交者可能失败

-- 应用层乐观锁
CREATE TABLE orders (
    id         NUMBER NOT NULL,
    status     VARCHAR(50),
    version    NUMBER NOT NULL DEFAULT 1,
    updated_at TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
);

-- 更新时检查版本
BEGIN TRANSACTION;
    UPDATE orders
    SET status = 'shipped',
        version = version + 1,
        updated_at = CURRENT_TIMESTAMP()
    WHERE id = 100 AND version = 5;
    -- 应用层检查更新行数
COMMIT;

-- ============================================================
-- Time Travel（时间旅行）
-- ============================================================

-- 使用 Time Travel 读取历史数据（不需要锁）
SELECT * FROM orders AT(TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP_NTZ);
SELECT * FROM orders AT(OFFSET => -60*5);  -- 5 分钟前
SELECT * FROM orders BEFORE(STATEMENT => 'query_id_here');

-- ============================================================
-- 资源监控
-- ============================================================

-- 查看运行中的查询
SELECT
    query_id,
    query_text,
    user_name,
    start_time,
    execution_status,
    total_elapsed_time
FROM TABLE(information_schema.query_history())
WHERE execution_status = 'RUNNING'
ORDER BY start_time DESC;

-- 查看锁等待的查询
SELECT
    query_id,
    query_text,
    blocked_query_id,
    user_name
FROM TABLE(information_schema.query_history())
WHERE blocked_query_id IS NOT NULL;

-- 取消查询
SELECT SYSTEM$CANCEL_QUERY('query_id_here');

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持行级锁（只有表级别的微分区锁）
-- 3. 不支持 LOCK TABLE 语句
-- 4. 不支持 advisory locks
-- 5. 并发 DML 可能因冲突而失败，需要应用层重试
-- 6. 隔离级别固定为 READ COMMITTED（MVCC 快照隔离）
-- 7. 长事务会持有锁较长时间，建议保持事务简短
-- 8. Time Travel 提供了不需要锁的历史数据访问
