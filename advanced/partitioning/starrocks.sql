-- StarRocks: 分区策略
--
-- 参考资料:
--   [1] StarRocks Documentation - Partition
--       https://docs.starrocks.io/docs/table_design/Data_distribution/

-- ============================================================
-- 1. 两层数据分布 (与 Doris 同源)
-- ============================================================
-- PARTITION(分区) + BUCKET(分桶) 两层设计，与 Doris 相同。
--
-- StarRocks 的差异化:
--   Expression Partition(3.1+): 自动按表达式创建分区
--   自动分桶(3.0+): 不需要指定 BUCKETS 数量

-- ============================================================
-- 2. RANGE 分区
-- ============================================================
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
DUPLICATE KEY(id)
PARTITION BY RANGE(order_date) (
    PARTITION p2023 VALUES [('2023-01-01'), ('2024-01-01')),
    PARTITION p2024 VALUES [('2024-01-01'), ('2025-01-01')),
    PARTITION p2025 VALUES [('2025-01-01'), ('2026-01-01'))
)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- ============================================================
-- 3. Expression Partition (3.1+，StarRocks 独有)
-- ============================================================
-- 按表达式自动创建分区，无需手动定义分区列表:
-- CREATE TABLE orders_auto (
--     id BIGINT, order_date DATE, amount DECIMAL(10,2)
-- ) DUPLICATE KEY(id)
-- PARTITION BY date_trunc('month', order_date)
-- DISTRIBUTED BY HASH(id);
--
-- 设计分析:
--   数据写入时，自动按 date_trunc 计算分区值并创建分区。
--   对比 Doris 动态分区: 需要配置 PROPERTIES，只支持时间维度。
--   Expression Partition 更灵活(支持任意表达式)。
--   类似 ClickHouse 的 PARTITION BY toYYYYMM(date)。

-- ============================================================
-- 4. 动态分区
-- ============================================================
CREATE TABLE logs (
    id       BIGINT,
    log_time DATETIME,
    message  VARCHAR(4000)
)
DUPLICATE KEY(id)
PARTITION BY RANGE(log_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p"
);

-- 与 Doris 完全相同的语法(同源)。

-- ============================================================
-- 5. 自动分桶 (3.0+)
-- ============================================================
CREATE TABLE auto_bucket (
    id   BIGINT,
    name VARCHAR(64)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id);   -- 不指定 BUCKETS，自动推断

-- 根据 BE 节点数和预估数据量自动计算 BUCKETS。
-- 对比 Doris: 必须手动指定 BUCKETS(截至 2.1)。

-- ============================================================
-- 6. 分区管理
-- ============================================================
ALTER TABLE orders ADD PARTITION p2026
    VALUES [('2026-01-01'), ('2027-01-01'));
ALTER TABLE orders DROP PARTITION p2023;

-- ============================================================
-- 7. StarRocks vs Doris 分区对比
-- ============================================================
-- Expression Partition:
--   StarRocks 3.1+: PARTITION BY expr(最灵活)
--   Doris 2.1+:     AUTO PARTITION(功能类似但语法不同)
--
-- 自动分桶:
--   StarRocks 3.0+: 支持(省略 BUCKETS)
--   Doris:          不支持(必须手动指定)
--
-- 动态分区:
--   两者相同(同源语法)
--
-- Colocate Group:
--   两者都支持(建表时 "colocate_with" = "group_name")
--   同组表的相同分桶键 → 本地 JOIN(零网络开销)
--
-- 对引擎开发者的启示:
--   分区设计的核心价值是 Partition Pruning:
--     WHERE order_date = '2024-01-15' → 只扫描 p2024_01
--     减少 I/O 是 OLAP 性能的关键。
--   Expression Partition 的实现需要在写入时"即时创建分区"——
--   这要求 FE 的元数据管理支持并发分区创建。
