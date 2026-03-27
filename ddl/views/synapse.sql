-- Azure Synapse Analytics: Views
--
-- 参考资料:
--   [1] Microsoft Documentation - CREATE VIEW (Synapse)
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-view-transact-sql
--   [2] Microsoft Documentation - Materialized Views (Synapse)
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/design-materialized-views-performance-tuning
--   [3] Microsoft Documentation - Synapse SQL Views
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/create-use-views

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR ALTER VIEW
-- 注意：Synapse 支持 CREATE VIEW，部分池支持 CREATE OR ALTER

-- ============================================
-- 物化视图 (Dedicated SQL Pool)
-- Synapse 原生支持物化视图
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary
WITH (DISTRIBUTION = HASH(user_id))          -- 必须指定分布方式
AS
SELECT user_id, COUNT_BIG(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 物化视图特性：
-- 1. 自动维护（DML 时自动更新）
-- 2. 自动查询重写（优化器透明使用）
-- 3. 支持 DISTRIBUTION: HASH, ROUND_ROBIN, REPLICATE

-- 重建物化视图
ALTER MATERIALIZED VIEW mv_order_summary REBUILD;

-- 禁用/启用自动维护
ALTER MATERIALIZED VIEW mv_order_summary DISABLE;
ALTER MATERIALIZED VIEW mv_order_summary ENABLE;    -- 重新启用并重建

-- 物化视图限制：
-- 1. 仅在 Dedicated SQL Pool 中支持
-- 2. 必须使用 COUNT_BIG 而非 COUNT
-- 3. 不支持 LEFT/RIGHT/FULL OUTER JOIN
-- 4. 不支持子查询
-- 5. 基表不能有 CDC

-- ============================================
-- 可更新视图
-- Synapse 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;

-- 限制：
-- 物化视图仅在 Dedicated SQL Pool 支持
-- Serverless SQL Pool 不支持物化视图
-- 不支持 WITH CHECK OPTION
-- 物化视图不支持所有 T-SQL 功能
-- 自动维护有存储和计算开销
