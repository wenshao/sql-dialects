-- Snowflake: 表分区策略
--
-- 参考资料:
--   [1] Snowflake Documentation - Micro-Partitions & Clustering
--       https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
--   [2] Snowflake Documentation - Clustering Keys
--       https://docs.snowflake.com/en/user-guide/tables-clustering-keys

-- Snowflake 不使用传统分区
-- 使用自动微分区（Micro-Partitions）和聚簇键（Clustering Keys）

-- ============================================================
-- 微分区（自动，无需用户操作）
-- ============================================================

-- Snowflake 自动将数据分成 50-500MB 的微分区
-- 每个微分区包含列存储的元数据：MIN/MAX 值

-- 创建普通表（自动微分区）
CREATE TABLE orders (
    id NUMBER, user_id NUMBER,
    amount NUMBER(10,2), order_date DATE
);

-- 查询时自动进行微分区裁剪
SELECT * FROM orders WHERE order_date = '2024-06-15';

-- ============================================================
-- 聚簇键（Clustering Key）
-- ============================================================

-- 定义聚簇键优化数据排列
CREATE TABLE events (
    event_id NUMBER, event_time TIMESTAMP,
    user_id NUMBER, event_type VARCHAR
) CLUSTER BY (event_time::DATE);

-- 多列聚簇
CREATE TABLE sales (
    id NUMBER, sale_date DATE,
    region VARCHAR, amount NUMBER
) CLUSTER BY (sale_date, region);

-- 为已有表添加聚簇键
ALTER TABLE orders CLUSTER BY (order_date);

-- 删除聚簇键
ALTER TABLE orders DROP CLUSTERING KEY;

-- ============================================================
-- 自动聚簇（Automatic Clustering）
-- ============================================================

-- Snowflake 自动维护聚簇状态
-- 查看聚簇深度
SELECT SYSTEM$CLUSTERING_DEPTH('orders');

-- 查看聚簇信息
SELECT SYSTEM$CLUSTERING_INFORMATION('orders');

-- 查看聚簇比率
SELECT SYSTEM$CLUSTERING_RATIO('orders');

-- 暂停/恢复自动聚簇
ALTER TABLE orders SUSPEND RECLUSTER;
ALTER TABLE orders RESUME RECLUSTER;

-- ============================================================
-- 分区裁剪效果
-- ============================================================

-- 查看查询扫描的微分区数量
SELECT query_id, partitions_scanned, partitions_total,
       bytes_scanned
FROM snowflake.account_usage.query_history
WHERE query_text LIKE '%orders%'
ORDER BY start_time DESC LIMIT 10;

-- ============================================================
-- 搜索优化服务（Enterprise+）
-- ============================================================

-- 为特定列启用搜索优化
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON EQUALITY(user_id);
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON SUBSTRING(username);

-- 注意：Snowflake 自动管理微分区，无需手动分区
-- 注意：聚簇键定义数据的物理排列顺序
-- 注意：自动聚簇在后台维护数据的聚簇状态
-- 注意：分区裁剪通过微分区的 MIN/MAX 元数据实现
-- 注意：聚簇键的选择应基于最常用的查询过滤列
-- 注意：搜索优化服务（Enterprise+）加速点查询
