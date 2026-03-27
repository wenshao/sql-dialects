-- Databricks SQL: 索引
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- Databricks SQL 没有传统索引（没有 B-tree、Hash 等）
-- 查询优化通过数据布局、统计信息和文件剪裁实现

-- ============================================================
-- Liquid Clustering（推荐，Databricks 2023+）
-- ============================================================
-- 取代传统分区和 Z-ORDER，自动维护数据布局

-- 创建表时指定 Liquid Clustering 键
CREATE TABLE orders (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id    BIGINT,
    amount     DECIMAL(10, 2),
    order_date DATE
)
CLUSTER BY (order_date, user_id);

-- 修改 Liquid Clustering 键（无需重写数据）
ALTER TABLE orders CLUSTER BY (order_date);
ALTER TABLE orders CLUSTER BY NONE;

-- 触发 Liquid Clustering 整理
OPTIMIZE orders;

-- ============================================================
-- Z-ORDER（与传统分区搭配使用）
-- ============================================================
-- 在分区内对数据进行多维排列

-- 分区表
CREATE TABLE events (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    event_type STRING,
    user_id    BIGINT,
    event_date DATE
)
PARTITIONED BY (event_date);

-- Z-ORDER 优化（在 OPTIMIZE 时指定）
OPTIMIZE events ZORDER BY (user_id, event_type);
OPTIMIZE events WHERE event_date >= '2024-01-01' ZORDER BY (user_id);

-- ============================================================
-- 数据跳跃（Data Skipping）
-- ============================================================
-- Delta Lake 自动收集每个文件中每列的 min/max/count 等统计信息
-- 查询时自动跳过不相关的文件

-- 查看表的统计信息
DESCRIBE DETAIL orders;
DESCRIBE EXTENDED orders;

-- 手动收集统计信息
ANALYZE TABLE orders COMPUTE STATISTICS;
ANALYZE TABLE orders COMPUTE STATISTICS FOR COLUMNS order_date, user_id;
ANALYZE TABLE orders COMPUTE STATISTICS NOSCAN;    -- 只收集表级统计

-- ============================================================
-- OPTIMIZE（文件合并与数据布局优化）
-- ============================================================

-- 合并小文件
OPTIMIZE orders;

-- 条件优化（只处理部分数据）
OPTIMIZE orders WHERE order_date >= '2024-01-01';

-- 自动优化（表属性）
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.autoOptimize.optimizeWrite' = 'true',     -- 写入时自动优化文件大小
    'delta.autoOptimize.autoCompact' = 'true'        -- 自动合并小文件
);

-- 目标文件大小
ALTER TABLE orders SET TBLPROPERTIES (
    'delta.targetFileSize' = '134217728'             -- 128 MB
);

-- ============================================================
-- Bloom Filter Index（布隆过滤器索引）
-- ============================================================
-- 适合等值查询的概率数据结构

-- 创建布隆过滤器索引（已弃用，推荐用 Liquid Clustering 替代）
-- CREATE BLOOMFILTER INDEX ON orders FOR COLUMNS (user_id);

-- ============================================================
-- VACUUM（清理过期文件）
-- ============================================================

VACUUM orders;                               -- 使用默认保留期（7 天）
VACUUM orders RETAIN 168 HOURS;              -- 指定保留期

-- 注意：VACUUM 不能恢复被删除的文件
-- 注意：VACUUM 后早于保留期的时间旅行将不可用

-- ============================================================
-- 物化视图
-- ============================================================

-- 创建物化视图
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
GROUP BY order_date;

-- 刷新物化视图
REFRESH MATERIALIZED VIEW mv_daily_sales;

-- ============================================================
-- 预测优化（Predictive Optimization）
-- ============================================================
-- Unity Catalog 管理的表可以启用预测优化
-- 系统自动运行 OPTIMIZE 和 VACUUM

ALTER TABLE orders SET TBLPROPERTIES (
    'delta.enableDeletionVectors' = 'true'           -- 启用删除向量（加速删除/更新）
);

-- ============================================================
-- 表信息查询
-- ============================================================

-- 查看表详细信息
DESCRIBE DETAIL orders;
DESCRIBE HISTORY orders;                      -- 查看变更历史
DESCRIBE EXTENDED orders;

-- 查看 Delta 日志
SELECT * FROM (DESCRIBE HISTORY orders) WHERE operation = 'OPTIMIZE';

-- 注意：Databricks 没有传统索引（B-tree / Hash）
-- 注意：Liquid Clustering 是推荐的数据布局优化方式
-- 注意：Z-ORDER 适合与传统分区搭配（Liquid Clustering 可替代二者）
-- 注意：Data Skipping 由 Delta Lake 自动实现
-- 注意：Photon 引擎对列式数据扫描有显著性能提升
-- 注意：预测优化由系统自动维护，减少 DBA 手动调优
