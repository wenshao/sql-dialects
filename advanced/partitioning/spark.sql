-- Spark SQL: 表分区策略
--
-- 参考资料:
--   [1] Spark Documentation - Partitioning
--       https://spark.apache.org/docs/latest/sql-data-sources-parquet.html#partition-discovery
--   [2] Delta Lake - Partitioning
--       https://docs.delta.io/latest/best-practices.html#choose-the-right-partition-column

-- ============================================================
-- Hive 风格分区
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) USING PARQUET
  PARTITIONED BY (order_date DATE);

-- 动态分区插入
INSERT INTO orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;

-- ============================================================
-- Delta Lake 分区
-- ============================================================

CREATE TABLE delta_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) USING DELTA
  PARTITIONED BY (order_date);

-- 分区裁剪
SELECT * FROM delta_orders WHERE order_date = '2024-06-15';

-- ============================================================
-- 分桶（Bucketing）
-- ============================================================

CREATE TABLE bucketed_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) USING PARQUET
  CLUSTERED BY (user_id) INTO 16 BUCKETS;

-- 分桶优化连接查询（避免 Shuffle）

-- ============================================================
-- 分区管理
-- ============================================================

-- 添加/删除分区
ALTER TABLE orders ADD PARTITION (order_date='2024-07-01');
ALTER TABLE orders DROP PARTITION (order_date='2023-01-01');

-- 修复分区
MSCK REPAIR TABLE orders;

-- Delta Lake: 优化（文件合并）
OPTIMIZE delta_orders WHERE order_date = '2024-06-15';

-- Delta Lake: Z-ORDER（多维聚簇）
OPTIMIZE delta_orders ZORDER BY (user_id, amount);

-- 注意：Spark 支持 Hive 风格分区和 Delta Lake 分区
-- 注意：分桶（Bucketing）可以优化连接查询
-- 注意：Delta Lake 的 OPTIMIZE + ZORDER 提供文件级优化
-- 注意：MSCK REPAIR TABLE 发现文件系统上的分区
-- 注意：分区列不应有太高的基数（避免小文件问题）
