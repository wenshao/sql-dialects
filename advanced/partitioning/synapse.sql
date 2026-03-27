-- Azure Synapse Analytics: 表分区策略
--
-- 参考资料:
--   [1] Microsoft Docs - Partitioned Tables (Synapse)
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-partition

-- ============================================================
-- 创建分区表
-- ============================================================

-- 步骤 1: 分区函数
CREATE PARTITION FUNCTION pf_date (DATE)
AS RANGE RIGHT FOR VALUES (
    '2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01'
);

-- 步骤 2: 分区方案
CREATE PARTITION SCHEME ps_date
AS PARTITION pf_date ALL TO ([PRIMARY]);

-- 步骤 3: 创建表（同时指定分布策略）
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
)
WITH (
    DISTRIBUTION = HASH(user_id),
    PARTITION (order_date RANGE RIGHT FOR VALUES (
        '2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01'
    ))
);

-- ============================================================
-- 分布 + 分区
-- ============================================================

-- Synapse 有两个维度：
-- 1. 分布（Distribution）：数据跨计算节点分布
--    HASH, ROUND_ROBIN, REPLICATE
-- 2. 分区（Partition）：每个分布内按范围分区

-- ============================================================
-- 分区管理
-- ============================================================

-- 分区切换
ALTER TABLE orders SWITCH PARTITION 3 TO orders_archive;

-- 拆分分区
ALTER TABLE orders SPLIT RANGE ('2027-01-01');

-- 合并分区
ALTER TABLE orders MERGE RANGE ('2023-01-01');

-- 清空分区
TRUNCATE TABLE orders WITH (PARTITIONS (3));

-- ============================================================
-- 查看分区信息
-- ============================================================

SELECT partition_number, rows
FROM sys.partitions
WHERE object_id = OBJECT_ID('orders')
AND index_id <= 1;

-- 注意：Synapse 使用分布 + 分区两个维度
-- 注意：分布控制跨节点分布，分区控制每个节点内的数据划分
-- 注意：分区切换（SWITCH）是元数据操作，非常快
-- 注意：选择合适的分布键减少数据移动
