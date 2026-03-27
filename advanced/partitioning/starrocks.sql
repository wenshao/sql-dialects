-- StarRocks: 表分区策略
--
-- 参考资料:
--   [1] StarRocks Documentation - Data Distribution
--       https://docs.starrocks.io/docs/table_design/Data_distribution/

-- ============================================================
-- RANGE 分区 + 分桶
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) PARTITION BY RANGE(order_date) (
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01')),
    PARTITION p2025 VALUES [('2025-01-01'), ('2026-01-01'))
) DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- ============================================================
-- 表达式分区（3.1+）
-- ============================================================

CREATE TABLE events (
    event_id BIGINT, event_time DATETIME, data STRING
) PARTITION BY date_trunc('month', event_time)
DISTRIBUTED BY HASH(event_id) BUCKETS 8;

-- 自动按月创建分区

-- ============================================================
-- LIST 分区
-- ============================================================

CREATE TABLE users_region (
    id BIGINT, username STRING, region STRING
) PARTITION BY LIST(region) (
    PARTITION p_east VALUES IN ('Shanghai'),
    PARTITION p_north VALUES IN ('Beijing')
) DISTRIBUTED BY HASH(id) BUCKETS 8;

-- ============================================================
-- 动态分区
-- ============================================================

CREATE TABLE logs (
    id BIGINT, log_time DATETIME, message STRING
) PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- ============================================================
-- 分区管理
-- ============================================================

ALTER TABLE orders ADD PARTITION p2026 VALUES [('2026-01-01'), ('2027-01-01'));
ALTER TABLE orders DROP PARTITION p2024;

-- 注意：StarRocks 使用分区 + 分桶两层划分
-- 注意：3.1+ 表达式分区自动创建分区
-- 注意：动态分区自动管理分区的生命周期
-- 注意：分桶数影响并行度和数据分布
