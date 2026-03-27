-- DuckDB: 表分区策略
--
-- 参考资料:
--   [1] DuckDB Documentation - Hive Partitioning
--       https://duckdb.org/docs/data/partitioning/hive_partitioning
--   [2] DuckDB Documentation - Partitioned Writes
--       https://duckdb.org/docs/data/partitioning/partitioned_writes

-- DuckDB 不支持传统的表级分区
-- 使用 Hive 风格分区读写外部文件

-- ============================================================
-- 读取 Hive 分区数据
-- ============================================================

-- 读取 Hive 风格分区的 Parquet 文件
SELECT * FROM read_parquet('data/orders/year=*/month=*/*.parquet',
    hive_partitioning = true);

-- 分区裁剪
SELECT * FROM read_parquet('data/orders/year=*/month=*/*.parquet',
    hive_partitioning = true)
WHERE year = 2024 AND month = 6;

-- ============================================================
-- 写入分区数据
-- ============================================================

-- 按分区写入 Parquet
COPY (SELECT *, YEAR(order_date) AS year, MONTH(order_date) AS month
      FROM orders)
TO 'output/orders' (FORMAT PARQUET, PARTITION_BY (year, month));

-- 使用 COPY 语句写入分区 CSV
COPY orders TO 'output/orders' (FORMAT CSV, PARTITION_BY (region));

-- ============================================================
-- 视图组织（替代分区）
-- ============================================================

CREATE VIEW partitioned_orders AS
SELECT *, YEAR(order_date) AS year FROM orders;

SELECT * FROM partitioned_orders WHERE year = 2024;

-- 注意：DuckDB 不支持表级分区
-- 注意：通过 Hive 分区格式读写外部文件实现分区
-- 注意：hive_partitioning = true 启用分区裁剪
-- 注意：PARTITION_BY 参数控制输出文件的分区方式
-- 注意：DuckDB 主要用于分析，通过文件分区管理大数据集
