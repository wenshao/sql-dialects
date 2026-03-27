-- Amazon Redshift: Views
--
-- 参考资料:
--   [1] Redshift Documentation - CREATE VIEW
--       https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_VIEW.html
--   [2] Redshift Documentation - CREATE MATERIALIZED VIEW
--       https://docs.aws.amazon.com/redshift/latest/dg/materialized-view-overview.html
--   [3] Redshift Documentation - Late-binding Views
--       https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_VIEW.html#r_CREATE_VIEW-late-binding-views

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 延迟绑定视图（Late-binding View）
-- 不检查基表是否存在，适合跨 schema 或外部表
CREATE VIEW late_binding_view AS
SELECT id, username, email
FROM users
WITH NO SCHEMA BINDING;

-- ============================================
-- 物化视图
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 自动刷新（Redshift 独有）
CREATE MATERIALIZED VIEW mv_auto_refresh
AUTO REFRESH YES                            -- 自动刷新
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_order_summary;

-- 物化视图特性：
-- 1. 支持 AUTO REFRESH YES（Redshift 自动管理刷新）
-- 2. 支持增量刷新（自动检测基表变更）
-- 3. 支持自动查询重写（优化器自动使用物化视图）

-- ============================================
-- 可更新视图
-- Redshift 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- 限制：
-- 不支持 WITH CHECK OPTION
-- 视图不可更新
-- WITH NO SCHEMA BINDING 视图不检查列类型
-- 物化视图不支持所有 SQL 功能（如某些窗口函数）
-- AUTO REFRESH 的刷新时机由 Redshift 决定
