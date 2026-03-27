-- Vertica: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Vertica Documentation - Transaction Processing
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/ConceptsGuide/Other/TransactionProcessing.htm
--   [2] Vertica Documentation - LOCKS System Table
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SystemTables/MONITOR/LOCKS.htm
--   [3] Vertica Documentation - LOCK_TIMEOUT
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/SET/SETLOCK_TIMEOUT.htm

-- ============================================================
-- Vertica 并发模型概述
-- ============================================================
-- Vertica 是列式分析数据库:
-- 1. 使用 MVCC（快照隔离）
-- 2. 读操作不阻塞写操作
-- 3. 写操作获取表级别的 INSERT/DELETE 锁
-- 4. 不支持行级锁
-- 5. 不支持 SELECT FOR UPDATE

-- ============================================================
-- 表级锁（自动管理）
-- ============================================================

-- Vertica 锁类型:
-- S (Shared): SELECT 获取
-- I (Insert): INSERT/COPY 获取
-- D (Delete): DELETE/UPDATE 获取
-- T (Table): DDL 操作获取
-- U (Usage): 使用 schema/database
-- O (Owner): 表拥有者操作
-- X (Exclusive): DROP/TRUNCATE

-- INSERT 和 DELETE 可以对同一表并发执行
-- DDL 操作需要排他锁

-- ============================================================
-- 锁超时
-- ============================================================

-- 设置锁超时（秒）
SET LOCK_TIMEOUT = 300;        -- 默认 300 秒

-- 查看当前设置
SHOW LOCK_TIMEOUT;

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INT DEFAULT 1 NOT NULL;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 事务
-- ============================================================

BEGIN;
    INSERT INTO orders VALUES (1, 'new', 100.00);
    UPDATE orders SET status = 'confirmed' WHERE id = 1;
COMMIT;

-- 隔离级别（只支持两种）
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- 默认
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- ============================================================
-- 锁监控
-- ============================================================

-- LOCKS 系统表
SELECT
    lock_mode,
    lock_scope,
    object_name,
    transaction_id,
    statement_id,
    grant_time
FROM V_MONITOR.LOCKS;

-- 查看锁等待
SELECT * FROM V_MONITOR.LOCKS WHERE lock_mode = 'X' OR grant_time IS NULL;

-- 查看活跃会话
SELECT * FROM V_MONITOR.SESSIONS WHERE is_active = TRUE;

-- 查看运行中的查询
SELECT * FROM V_MONITOR.QUERY_REQUESTS WHERE is_executing = TRUE;

-- 终止会话
SELECT CLOSE_SESSION('session_id');
SELECT INTERRUPT_STATEMENT('session_id', statement_id);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE 语句
-- 3. 不支持 advisory locks
-- 4. INSERT 和 DELETE 可以并发执行
-- 5. UPDATE = DELETE + INSERT（内部实现）
-- 6. DDL 操作需要排他锁
-- 7. 适合大批量分析操作，不适合高并发 OLTP
