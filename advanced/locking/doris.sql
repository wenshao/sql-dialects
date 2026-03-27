-- Apache Doris: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Apache Doris Documentation - Data Model
--       https://doris.apache.org/docs/data-table/data-model
--   [2] Apache Doris Documentation - Transaction
--       https://doris.apache.org/docs/data-operate/transaction

-- ============================================================
-- Doris 并发模型概述
-- ============================================================
-- Doris 是 MPP 分析数据库:
-- 1. 不支持传统的行级锁
-- 2. 使用 MVCC 实现读写并发
-- 3. 写入通过批量导入完成
-- 4. 使用表级别的元数据锁
-- 5. 不支持 SELECT FOR UPDATE

-- ============================================================
-- 事务（Doris 2.0+ 增强）
-- ============================================================

-- 两阶段提交（用于 Stream Load 等导入操作）
BEGIN;
    -- ... 批量写入操作 ...
COMMIT;

-- 导入事务是原子的
-- 导入成功则全部可见，失败则全部回滚

-- ============================================================
-- 数据模型与并发
-- ============================================================

-- Aggregate 模型: 相同 Key 的行自动聚合
-- Unique 模型: 相同 Key 保留最新值（类似 upsert）
-- Duplicate 模型: 保留所有行

-- Unique 模型（Merge-on-Write，Doris 1.2+）
CREATE TABLE orders (
    id      BIGINT,
    status  VARCHAR(50),
    amount  DECIMAL(10,2),
    version INT
)
UNIQUE KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true"
);

-- ============================================================
-- 乐观锁（应用层）
-- ============================================================

-- Unique Key 表模式下通过 version 列实现
-- 新插入相同 Key 的行会覆盖旧行
INSERT INTO orders VALUES (100, 'shipped', 99.99, 6);
-- 如果 version = 6 > 旧版本，则覆盖成功

-- ============================================================
-- 表级别操作锁
-- ============================================================

-- Schema Change 获取表级排他锁
ALTER TABLE orders ADD COLUMN new_col INT;

-- 导入操作之间可以并发
-- 但 Schema Change 与导入互斥

-- ============================================================
-- 监控
-- ============================================================

-- 查看正在运行的导入任务
SHOW LOAD;

-- 查看正在运行的查询
SHOW PROC '/current_queries';

-- 取消查询
CANCEL LOAD WHERE LABEL = 'load_label';
KILL query_id;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE
-- 3. 不支持 advisory locks
-- 4. 写入通过批量导入（Stream Load / Broker Load / Insert Into）
-- 5. Unique Key 表提供 upsert 语义
-- 6. 适合分析型工作负载
