-- Synapse: 缓慢变化维度 (Slowly Changing Dimension)
--
-- 参考资料:
--   [1] Azure Synapse Analytics - 兼容 SQL Server T-SQL
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- ============================================================
-- SCD Type 1: MERGE (与 SQL Server 语法相同，部分池支持)
-- ============================================================
-- Dedicated SQL Pool 支持有限的 MERGE
-- 推荐使用 CTAS (CREATE TABLE AS SELECT) 模式

-- CTAS 模式（Synapse 推荐）
CREATE TABLE dim_customer_new
WITH (DISTRIBUTION = HASH(customer_id))
AS
SELECT COALESCE(s.customer_id, d.customer_id) AS customer_id,
       COALESCE(s.name, d.name) AS name,
       COALESCE(s.city, d.city) AS city,
       COALESCE(s.tier, d.tier) AS tier
FROM dim_customer d
FULL OUTER JOIN stg_customer s ON d.customer_id = s.customer_id;

RENAME OBJECT dim_customer TO dim_customer_old;
RENAME OBJECT dim_customer_new TO dim_customer;
DROP TABLE dim_customer_old;
