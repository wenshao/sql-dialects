-- Hologres: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Hologres 文档 - 并发写入
--       https://help.aliyun.com/document_detail/312450.html
--   [2] Hologres 文档 - 行存表与列存表
--       https://help.aliyun.com/document_detail/160755.html

-- ============================================================
-- Hologres 并发模型概述
-- ============================================================
-- Hologres 是阿里云实时数仓（兼容 PostgreSQL）:
-- 1. 支持行存和列存表
-- 2. 使用 MVCC 和乐观并发控制
-- 3. 支持 SELECT FOR UPDATE（行存表）
-- 4. 高并发写入通过主键 upsert 实现

-- ============================================================
-- 行级锁（行存表）
-- ============================================================

-- SELECT FOR UPDATE（行存表支持）
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

-- NOWAIT
SELECT * FROM orders WHERE id = 100 FOR UPDATE NOWAIT;

-- ============================================================
-- 主键冲突处理（高并发 upsert）
-- ============================================================

-- INSERT ON CONFLICT（upsert）
INSERT INTO orders (id, status, amount)
VALUES (100, 'shipped', 99.99)
ON CONFLICT (id)
DO UPDATE SET status = EXCLUDED.status, amount = EXCLUDED.amount;

-- INSERT IGNORE（忽略冲突）
INSERT INTO orders (id, status, amount)
VALUES (100, 'shipped', 99.99)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 乐观锁
-- ============================================================

ALTER TABLE orders ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 锁监控（兼容 PostgreSQL）
-- ============================================================

SELECT * FROM pg_locks;
SELECT * FROM pg_stat_activity WHERE state = 'active';

-- ============================================================
-- 事务隔离级别
-- ============================================================

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;      -- 默认

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 行存表支持 SELECT FOR UPDATE
-- 2. 列存表不支持 SELECT FOR UPDATE
-- 3. 高并发写入推荐使用 INSERT ON CONFLICT（upsert）
-- 4. 兼容部分 PostgreSQL 锁语法
-- 5. 适合实时数仓 HSAP 场景
