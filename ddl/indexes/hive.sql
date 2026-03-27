-- Hive: 索引
--
-- 参考资料:
--   [1] Apache Hive - Indexing
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Indexing
--   [2] Apache Hive Language Manual - DDL
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL

-- Hive 3.0 已废弃索引功能
-- 之前版本的索引语法（已废弃，仅供参考）：
-- CREATE INDEX idx_username ON TABLE users (username)
--     AS 'org.apache.hadoop.hive.ql.index.compact.CompactIndexHandler'
--     WITH DEFERRED REBUILD IN TABLE idx_username_table;

-- 查询优化通过分区、分桶和文件格式实现

-- ============================================================
-- 分区（Partitioning）—— 最重要的优化手段
-- ============================================================

CREATE TABLE orders (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING, region STRING)
STORED AS ORC;

-- 添加分区
ALTER TABLE orders ADD PARTITION (dt = '20240115', region = 'us');

-- 动态分区（根据数据自动创建分区）
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT OVERWRITE TABLE orders PARTITION (dt, region)
SELECT id, user_id, amount, dt, region FROM staging_orders;

-- 分区剪裁（查询时指定分区条件）
SELECT * FROM orders WHERE dt = '20240115';

-- ============================================================
-- 分桶（Bucketing）
-- ============================================================

CREATE TABLE orders_bucketed (
    id       BIGINT,
    user_id  BIGINT,
    amount   DECIMAL(10,2)
)
PARTITIONED BY (dt STRING)
CLUSTERED BY (user_id) SORTED BY (id) INTO 256 BUCKETS
STORED AS ORC;

-- 分桶优化 JOIN（Bucket Map Join）
SET hive.optimize.bucketmapjoin = true;

-- ============================================================
-- ORC/Parquet 内置索引
-- ============================================================

-- ORC 文件自带行组级别的统计信息（min/max/count/sum）
-- Parquet 文件自带列级别的统计信息
-- 查询引擎自动利用这些统计信息进行谓词下推

-- ORC 压缩和优化
CREATE TABLE logs (
    timestamp TIMESTAMP,
    level     STRING,
    message   STRING
)
STORED AS ORC
TBLPROPERTIES (
    'orc.compress' = 'ZLIB',
    'orc.bloom.filter.columns' = 'level',     -- 布隆过滤器
    'orc.bloom.filter.fpp' = '0.05'
);

-- ============================================================
-- 物化视图（Hive 3.0+）
-- ============================================================

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT dt, SUM(amount) AS total
FROM orders
GROUP BY dt;

-- 自动重写查询使用物化视图

-- ============================================================
-- CBO（Cost-Based Optimizer）
-- ============================================================

-- 收集统计信息，帮助优化器选择最佳执行计划
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, email;

-- 注意：Hive 3.0 已正式废弃索引功能
-- 注意：分区 + ORC/Parquet 的内置统计信息是最主要的优化方式
-- 注意：ORC 布隆过滤器可以加速等值查询
-- 注意：Hive 是批处理引擎，不需要 OLTP 风格的索引
