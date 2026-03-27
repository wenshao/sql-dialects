-- Hive: 表分区策略
--
-- 参考资料:
--   [1] Apache Hive Documentation - Partitioned Tables
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-PartitionedTables
--   [2] Apache Hive Documentation - Dynamic Partitions
--       https://cwiki.apache.org/confluence/display/Hive/DynamicPartitions

-- ============================================================
-- 静态分区
-- ============================================================

CREATE TABLE orders (
    id BIGINT, user_id BIGINT, amount DECIMAL(10,2)
) PARTITIONED BY (order_date STRING)
  STORED AS PARQUET;

-- 添加分区
ALTER TABLE orders ADD PARTITION (order_date='2024-01-01')
    LOCATION '/data/orders/2024-01-01';

-- 插入到指定分区
INSERT INTO orders PARTITION (order_date='2024-01-01')
VALUES (1, 100, 99.99);

-- ============================================================
-- 多级分区
-- ============================================================

CREATE TABLE logs (
    id BIGINT, message STRING
) PARTITIONED BY (year INT, month INT, day INT)
  STORED AS ORC;

ALTER TABLE logs ADD PARTITION (year=2024, month=6, day=15);

-- ============================================================
-- 动态分区
-- ============================================================

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT INTO orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM raw_orders;
-- 自动根据 order_date 值创建分区

-- ============================================================
-- 分区管理
-- ============================================================

-- 查看分区
SHOW PARTITIONS orders;

-- 删除分区
ALTER TABLE orders DROP PARTITION (order_date='2023-01-01');

-- 修改分区位置
ALTER TABLE orders PARTITION (order_date='2024-01-01')
    SET LOCATION '/new/path/2024-01-01';

-- 修复分区（从文件系统自动发现）
MSCK REPAIR TABLE orders;

-- 注意：Hive 分区对应 HDFS 目录
-- 注意：动态分区自动根据数据值创建分区目录
-- 注意：MSCK REPAIR TABLE 自动发现文件系统上的分区
-- 注意：多级分区创建多层目录结构
-- 注意：分区裁剪是 Hive 查询性能的关键
