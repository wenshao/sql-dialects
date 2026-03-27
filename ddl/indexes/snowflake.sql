-- Snowflake: 索引
--
-- 参考资料:
--   [1] Snowflake - Search Optimization Service
--       https://docs.snowflake.com/en/user-guide/search-optimization-service
--   [2] Snowflake SQL Reference - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table

-- Snowflake 不支持传统索引
-- 查询优化通过微分区（Micro-partitions）和自动优化实现

-- ============================================================
-- 微分区（Micro-partitions）
-- ============================================================
-- Snowflake 自动将数据分成 50-500MB 的微分区
-- 每个微分区记录列的 min/max 统计信息
-- 查询时自动进行分区剪裁（Partition Pruning）

-- 查看表的微分区信息
SELECT SYSTEM$CLUSTERING_INFORMATION('orders');

-- ============================================================
-- 聚集键（Clustering Key）—— 最接近索引的优化手段
-- ============================================================

-- 创建表时指定聚集键
CREATE TABLE orders (
    id         NUMBER,
    user_id    NUMBER,
    amount     NUMBER(10,2),
    order_date DATE
)
CLUSTER BY (order_date, user_id);

-- 修改聚集键
ALTER TABLE orders CLUSTER BY (order_date);
ALTER TABLE orders DROP CLUSTERING KEY;

-- 聚集键不是索引，而是指导微分区内数据的物理排列
-- Snowflake 后台自动重聚集（Automatic Reclustering）

-- 查看聚集信息
SELECT SYSTEM$CLUSTERING_INFORMATION('orders', '(order_date)');
SELECT SYSTEM$CLUSTERING_DEPTH('orders');

-- ============================================================
-- 搜索优化服务（Search Optimization Service）
-- ============================================================
-- 企业版功能，加速等值查询和 LIKE/IN 查询

ALTER TABLE users ADD SEARCH OPTIMIZATION;
ALTER TABLE users ADD SEARCH OPTIMIZATION ON EQUALITY(username);
ALTER TABLE users ADD SEARCH OPTIMIZATION ON EQUALITY(email), SUBSTRING(bio);
ALTER TABLE users ADD SEARCH OPTIMIZATION ON GEO(location);

ALTER TABLE users DROP SEARCH OPTIMIZATION ON EQUALITY(username);
ALTER TABLE users DROP SEARCH OPTIMIZATION;

-- ============================================================
-- 物化视图（Materialized View）
-- ============================================================
-- 企业版功能，自动维护预计算结果

CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, SUM(amount) AS total
FROM orders
GROUP BY order_date;

-- 查询时自动使用物化视图

-- ============================================================
-- 查询加速服务（Query Acceleration Service）
-- ============================================================
-- 自动将大查询的部分工作分发到额外的计算资源
ALTER WAREHOUSE my_wh SET QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8;

-- 注意：Snowflake 没有 B-tree / Hash / GIN 等传统索引
-- 注意：聚集键控制数据的物理排列，不是索引结构
-- 注意：Search Optimization 创建后台数据结构加速点查
-- 注意：Snowflake 的理念是自动优化，减少 DBA 手动调优
