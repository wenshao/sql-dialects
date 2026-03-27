-- StarRocks: 锁机制 (Locking)
--
-- 参考资料:
--   [1] StarRocks Documentation - Data Models
--       https://docs.starrocks.io/docs/table_design/table_types/
--   [2] StarRocks Documentation - Loading Overview
--       https://docs.starrocks.io/docs/loading/Loading_intro/

-- ============================================================
-- StarRocks 并发模型概述
-- ============================================================
-- StarRocks 是 MPP 分析数据库（Doris 分支）:
-- 1. 不支持传统的行级锁
-- 2. 使用 MVCC 实现读写并发
-- 3. 写入通过批量导入或 INSERT INTO
-- 4. 不支持 SELECT FOR UPDATE

-- ============================================================
-- 事务
-- ============================================================

-- StarRocks 3.0+ 支持显式事务
BEGIN;
    INSERT INTO orders VALUES (1, 'new', 100.00);
    INSERT INTO orders VALUES (2, 'new', 200.00);
COMMIT;

-- 导入事务原子性
-- Stream Load / Broker Load / Routine Load 都是原子操作

-- ============================================================
-- Primary Key 表（实时更新）
-- ============================================================

-- Primary Key 表支持实时更新和删除
CREATE TABLE orders (
    id      BIGINT,
    status  VARCHAR(50),
    amount  DECIMAL(10,2),
    version INT
)
PRIMARY KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- UPDATE/DELETE 支持
UPDATE orders SET status = 'shipped' WHERE id = 100;
DELETE FROM orders WHERE status = 'cancelled';

-- ============================================================
-- 乐观锁（应用层）
-- ============================================================

-- 使用 version 列
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 并发控制
-- ============================================================

-- Schema Change 与导入互斥
-- 多个导入任务可以并发执行（不同的 tablet）
-- 同一 tablet 的写入串行化

-- ============================================================
-- 监控
-- ============================================================

SHOW LOAD;
SHOW PROCESSLIST;
KILL connection_id;

-- 查看 BE (Backend) 状态
-- 通过 FE/BE Web UI 监控

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE
-- 3. Primary Key 表支持 UPDATE/DELETE
-- 4. MVCC 提供快照读
-- 5. 适合实时分析场景
