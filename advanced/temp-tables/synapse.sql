-- Azure Synapse Analytics: 临时表与临时存储
--
-- 参考资料:
--   [1] Microsoft Docs - Temporary Tables (Synapse)
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-temporary

-- ============================================================
-- 本地临时表（#）
-- ============================================================

CREATE TABLE #temp_users (
    id BIGINT, username NVARCHAR(100), email NVARCHAR(200)
)
WITH (DISTRIBUTION = ROUND_ROBIN);

SELECT user_id, SUM(amount) AS total
INTO #temp_orders
FROM orders GROUP BY user_id;

-- ============================================================
-- 分布策略
-- ============================================================

CREATE TABLE #temp_hash (
    user_id BIGINT, total DECIMAL(10,2)
)
WITH (DISTRIBUTION = HASH(user_id));

CREATE TABLE #temp_replicate (
    id INT, name NVARCHAR(100)
)
WITH (DISTRIBUTION = REPLICATE);

-- ============================================================
-- 全局临时表（##）
-- ============================================================

CREATE TABLE ##global_config (
    key NVARCHAR(100), value NVARCHAR(1000)
)
WITH (DISTRIBUTION = ROUND_ROBIN);

-- 对所有会话可见

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- CETAS（CREATE EXTERNAL TABLE AS SELECT）
-- ============================================================

-- 将结果导出到外部存储
CREATE EXTERNAL TABLE staging.ext_results
WITH (
    LOCATION = '/staging/results/',
    DATA_SOURCE = my_storage,
    FILE_FORMAT = my_parquet_format
)
AS SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 注意：Synapse 临时表支持分布策略
-- 注意：选择正确的分布策略减少数据移动
-- 注意：REPLICATE 分布适合小型临时查找表
-- 注意：CETAS 可以将中间结果导出到外部存储
-- 注意：临时表在 Synapse 中广泛用于 ELT 流程
