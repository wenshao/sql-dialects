-- MaxCompute (ODPS): 索引
--
-- 参考资料:
--   [1] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

-- MaxCompute 不支持传统索引
-- 查询优化通过分区、分桶和数据组织方式实现

-- ============================================================
-- 分区（Partitioning）—— 最核心的优化手段
-- ============================================================

-- 单级分区
CREATE TABLE orders (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING);

-- 多级分区
CREATE TABLE logs (
    id      BIGINT,
    message STRING
)
PARTITIONED BY (dt STRING, region STRING, hour STRING);

-- 添加分区
ALTER TABLE orders ADD PARTITION (dt = '20240115');

-- 查询时指定分区（分区剪裁）
SELECT * FROM orders WHERE dt = '20240115';

-- 查看分区信息
SHOW PARTITIONS orders;

-- ============================================================
-- 分桶（Clustering / Bucketing）
-- ============================================================

-- 聚集表（Hash Clustering）
CREATE TABLE orders_clustered (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

-- 范围聚集（Range Clustering）
CREATE TABLE orders_range (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
RANGE CLUSTERED BY (user_id) SORTED BY (id) INTO 1024 BUCKETS;

-- ============================================================
-- 列存储优化
-- ============================================================

-- MaxCompute 默认使用列式存储
-- 查询时只读取需要的列，减少 IO

-- 小文件合并优化
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

-- ============================================================
-- 物化视图（Materialized View）
-- ============================================================

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT dt, SUM(amount) AS total
FROM orders
GROUP BY dt;

-- 注意：MaxCompute 没有 B-tree / Hash / 全文等传统索引
-- 注意：分区是最重要的性能优化手段，务必在查询中利用分区剪裁
-- 注意：分桶可以优化 JOIN 和聚合操作
-- 注意：列式存储自动优化列投影查询
-- 注意：作为离线计算引擎，MaxCompute 的设计不需要传统索引
