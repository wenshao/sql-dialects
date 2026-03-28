-- Spark SQL: 表分区策略 (Partitioning)
--
-- 参考资料:
--   [1] Spark SQL - Partition Discovery
--       https://spark.apache.org/docs/latest/sql-data-sources-parquet.html#partition-discovery
--   [2] Delta Lake - Partitioning Best Practices
--       https://docs.delta.io/latest/best-practices.html#choose-the-right-partition-column

-- ============================================================
-- 1. 核心设计: 目录级分区（Hive 风格）
-- ============================================================

-- Spark SQL 的分区是文件系统目录，而非数据库引擎内部的数据组织
CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) USING PARQUET
PARTITIONED BY (order_date DATE);

-- 物理布局:
-- /warehouse/orders/order_date=2024-01-01/part-00000.parquet
-- /warehouse/orders/order_date=2024-01-02/part-00001.parquet
-- /warehouse/orders/order_date=2024-01-03/part-00000.parquet
--
-- 分区列不在数据文件中——值编码在目录名中（key=value 格式）
-- 查询时通过目录名做 Partition Pruning（不需要打开文件就能跳过不相关分区）
--
-- 对比:
--   MySQL:      分区是引擎内部数据组织，分区键必须在主键中
--   PostgreSQL: 分区是独立子表（10+声明式），分区键必须在主键中
--   Oracle:     分区功能最丰富（INTERVAL/REFERENCE/COMPOSITE），不要求分区键在主键中
--   Hive:       与 Spark 完全一致（Spark 继承 Hive 的分区模型）
--   ClickHouse: PARTITION BY 表达式灵活，但也是目录级别
--   BigQuery:   只支持 DATE/TIMESTAMP/INT 列分区，自动管理目录
--   Flink SQL:  分区语义与 Hive/Spark 一致（PARTITIONED BY）
--   MaxCompute: Hash/Range 分区 + 二级分区

-- ============================================================
-- 2. 动态分区写入
-- ============================================================

-- 静态分区（指定分区值）
INSERT INTO orders PARTITION (order_date = '2024-01-15')
SELECT id, user_id, amount FROM raw_orders
WHERE order_date = '2024-01-15';

-- 动态分区（从数据中推导分区值）
INSERT INTO orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;

-- 动态分区覆盖模式: 只覆盖有数据的分区，保留其他分区
SET spark.sql.sources.partitionOverwriteMode = dynamic;
INSERT OVERWRITE TABLE orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;

-- 设计分析: 动态分区覆盖 vs 静态分区覆盖
--   静态: INSERT OVERWRITE ... PARTITION (order_date = '2024-01-15')
--         只覆盖指定分区，安全但需要知道分区值
--   动态(dynamic): INSERT OVERWRITE ... PARTITION (order_date)
--         只覆盖数据中出现的分区，其他分区不受影响
--   动态(static): INSERT OVERWRITE TABLE orders
--         覆盖整张表的所有分区——危险！
--
-- 对引擎开发者的启示:
--   partitionOverwriteMode = dynamic 是 Spark 3.0+ 的重要改进。
--   之前的默认行为（static）经常导致数据丢失——INSERT OVERWRITE 会删除所有分区。
--   如果你的引擎支持 INSERT OVERWRITE + 分区，务必提供动态覆盖选项。

-- ============================================================
-- 3. Delta Lake 分区
-- ============================================================

CREATE TABLE delta_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) USING DELTA
PARTITIONED BY (order_date);

-- 分区裁剪
SELECT * FROM delta_orders WHERE order_date = '2024-06-15';

-- Delta Lake 的分区建议:
--   每个分区至少 1GB 数据（避免小文件问题）
--   分区列基数不超过几千（万级分区 = 万级目录 = Metastore 压力）
--   不要按高基数列分区（如 user_id）——改用 Z-ORDER

-- ============================================================
-- 4. 分桶（Bucketing）: Hash 分布优化 JOIN
-- ============================================================

CREATE TABLE bucketed_orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2), order_date DATE
) USING PARQUET
CLUSTERED BY (user_id) INTO 16 BUCKETS;

-- 分桶原理:
--   对 user_id 做 Hash % 16，将数据分到 16 个文件中
--   两表按相同列和桶数分桶时，JOIN 可以避免 Shuffle（Bucket Join）
--   等价于预先做了 Hash Partitioning
--
-- 分桶 vs 分区:
--   分区: 按列值分目录，适合低基数列（日期、地区）
--   分桶: 按 Hash 值分文件，适合高基数列（user_id、order_id）
--
-- 实践中分桶使用率不高的原因:
--   1. 写入端必须严格控制桶数和分布
--   2. AQE 在很多场景下能自动优化 JOIN（减少了手动分桶的必要性）
--   3. Delta Lake 的 Z-ORDER + Liquid Clustering 是更灵活的替代方案

-- ============================================================
-- 5. Delta Lake OPTIMIZE: 文件合并与优化
-- ============================================================

-- 合并小文件（解决小文件问题）
OPTIMIZE delta_orders;

-- 只优化特定分区
OPTIMIZE delta_orders WHERE order_date = '2024-06-15';

-- Z-ORDER 多维聚簇
OPTIMIZE delta_orders ZORDER BY (user_id, amount);

-- VACUUM 清理过期文件
VACUUM delta_orders;                             -- 默认 7 天保留
VACUUM delta_orders RETAIN 168 HOURS;

-- ============================================================
-- 6. 分区管理
-- ============================================================

ALTER TABLE orders ADD PARTITION (order_date='2024-07-01');
ALTER TABLE orders DROP PARTITION (order_date='2023-01-01');

-- 修复分区（同步文件系统 -> Metastore）
MSCK REPAIR TABLE orders;

-- 查看分区
SHOW PARTITIONS orders;
DESCRIBE EXTENDED orders;

-- ============================================================
-- 7. Iceberg: Hidden Partitioning（更优雅的分区设计）
-- ============================================================

-- Iceberg 的 Hidden Partitioning 对用户透明:
-- CREATE TABLE catalog.db.events (
--     id BIGINT, event_time TIMESTAMP, user_id BIGINT
-- ) USING ICEBERG
-- PARTITIONED BY (days(event_time), bucket(16, user_id));
--
-- 用户查询: SELECT * FROM events WHERE event_time > '2024-01-01'
-- Iceberg 自动转换为分区裁剪——用户不需要知道分区是按天还是按月
--
-- 这解决了 Hive/Spark 分区的最大痛点:
--   用户必须知道分区列，并在查询中使用精确的分区值
--   否则无法触发分区裁剪

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Spark 2.0: Hive 风格分区、分桶
-- Spark 3.0: 动态分区裁剪、AQE 减少分桶依赖
-- Spark 3.0: partitionOverwriteMode = dynamic
-- Delta 1.0: OPTIMIZE + Z-ORDER
-- Iceberg:   Hidden Partitioning + Partition Evolution
-- Databricks: Liquid Clustering（Z-ORDER 的进化版，增量聚簇）
--
-- 分区设计建议:
--   分区列基数不超过几千（避免小文件和 Metastore 压力）
--   每个分区至少 1GB 数据
--   高基数列用 Z-ORDER 而非分区
--   新项目优先考虑 Iceberg 的 Hidden Partitioning
