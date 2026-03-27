-- Apache Doris: 表分区策略
--
-- 参考资料:
--   [1] Doris Documentation - Data Partition
--       https://doris.apache.org/docs/table-design/data-partition

-- ============================================================
-- RANGE 分区 + HASH 分桶
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) PARTITION BY RANGE(order_date) (
    PARTITION p2023 VALUES [('2023-01-01'), ('2024-01-01')),
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01')),
    PARTITION p2025 VALUES [('2025-01-01'), ('2026-01-01'))
) DISTRIBUTED BY HASH(user_id) BUCKETS 16
PROPERTIES ("replication_num" = "3");

-- ============================================================
-- 动态分区（自动创建和删除）
-- ============================================================

CREATE TABLE logs (
    id BIGINT, log_time DATETIME, message VARCHAR(4000)
) PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);

-- ============================================================
-- LIST 分区
-- ============================================================

CREATE TABLE users_region (
    id BIGINT, username VARCHAR(100), region VARCHAR(20)
) PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Shanghai', 'Hangzhou'),
    PARTITION p_north VALUES IN ('Beijing', 'Tianjin')
) DISTRIBUTED BY HASH(id) BUCKETS 8;

-- ============================================================
-- 分区管理
-- ============================================================

ALTER TABLE orders ADD PARTITION p2026
    VALUES [('2026-01-01'), ('2027-01-01'));
ALTER TABLE orders DROP PARTITION p2023;

-- 注意：Doris 使用分区 + 分桶两层数据划分
-- 注意：动态分区自动创建和删除分区（按天/周/月）
-- 注意：分桶（Bucket）控制分区内的数据分布
-- 注意：RANGE 分区的区间是左闭右开 [start, end)
