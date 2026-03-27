-- BigQuery: Views
--
-- 参考资料:
--   [1] BigQuery SQL Reference - CREATE VIEW
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_view_statement
--   [2] BigQuery Documentation - Materialized Views
--       https://cloud.google.com/bigquery/docs/materialized-views-intro
--   [3] BigQuery Documentation - Authorized Views
--       https://cloud.google.com/bigquery/docs/authorized-views

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW myproject.mydataset.active_users AS
SELECT id, username, email, created_at
FROM myproject.mydataset.users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW myproject.mydataset.active_users AS
SELECT id, username, email, created_at
FROM myproject.mydataset.users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS myproject.mydataset.active_users AS
SELECT id, username, email, created_at
FROM myproject.mydataset.users
WHERE age >= 18;

-- 带描述的视图
CREATE VIEW myproject.mydataset.order_summary
OPTIONS (
    description = 'Aggregated order summary by user',
    labels = [('env', 'prod')]
) AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM myproject.mydataset.orders
GROUP BY user_id;

-- ============================================
-- 物化视图 (Materialized View)
-- BigQuery 原生支持物化视图
-- ============================================
CREATE MATERIALIZED VIEW myproject.mydataset.mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM myproject.mydataset.orders
GROUP BY user_id;

-- 带刷新设置的物化视图
CREATE MATERIALIZED VIEW myproject.mydataset.mv_daily_stats
OPTIONS (
    enable_refresh = true,                  -- 自动刷新（默认 true）
    refresh_interval_minutes = 30           -- 刷新间隔（默认 30 分钟）
) AS
SELECT
    DATE(order_date) AS day,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM myproject.mydataset.orders
GROUP BY day;

-- 禁用自动刷新的物化视图（手动刷新）
CREATE MATERIALIZED VIEW myproject.mydataset.mv_manual
OPTIONS (
    enable_refresh = false
) AS
SELECT user_id, COUNT(*) AS cnt
FROM myproject.mydataset.orders
GROUP BY user_id;

-- 手动刷新（需要通过 BigQuery API 或 bq 命令行）
-- CALL BQ.REFRESH_MATERIALIZED_VIEW('myproject.mydataset.mv_manual');

-- 物化视图限制:
-- 1. 仅支持单表聚合查询（不支持 JOIN）
-- 2. 聚合函数限于: COUNT, SUM, AVG, MIN, MAX, COUNT DISTINCT, HLL_COUNT, APPROX_COUNT_DISTINCT 等
-- 3. 基表必须分区或聚集
-- 4. 不支持 HAVING, ORDER BY, LIMIT
-- 5. BigQuery 会自动利用物化视图优化查询（smart tuning）

-- ============================================
-- 可更新视图
-- BigQuery 视图不可更新（不支持对视图执行 INSERT/UPDATE/DELETE）
-- ============================================
-- 替代方案：使用 MERGE 或直接操作基表

-- ============================================
-- Authorized View（授权视图）
-- BigQuery 特有的安全机制，跨数据集访问
-- ============================================
-- 通过 BigQuery 控制台或 API 授权视图访问其他数据集
-- 授权视图可以绕过行级安全策略

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW myproject.mydataset.active_users;
DROP VIEW IF EXISTS myproject.mydataset.active_users;
DROP MATERIALIZED VIEW myproject.mydataset.mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS myproject.mydataset.mv_order_summary;

-- 注意：BigQuery 视图没有索引概念
-- 注意：物化视图的自动刷新由 BigQuery 内部管理
-- 注意：视图引用的表被删除后，视图会变为无效状态
