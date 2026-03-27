-- MaxCompute (ODPS): Views
--
-- 参考资料:
--   [1] MaxCompute Documentation - CREATE VIEW
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/create-view
--   [2] MaxCompute Documentation - Materialized View
--       https://www.alibabacloud.com/help/en/maxcompute/user-guide/materialized-view-operations

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

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 带注释的视图
CREATE VIEW order_summary
COMMENT 'Order aggregation by user'
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- ============================================
-- 物化视图 (MaxCompute 支持)
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary
LIFECYCLE 30                                 -- 生命周期 30 天
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 刷新物化视图
ALTER MATERIALIZED VIEW mv_order_summary REBUILD;

-- 物化视图自动查询改写
-- MaxCompute 优化器可以自动将查询重写为使用物化视图

-- 禁用自动改写
-- ALTER MATERIALIZED VIEW mv_order_summary DISABLE REWRITE;

-- ============================================
-- 可更新视图
-- MaxCompute 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;

-- 限制：
-- 不支持 WITH CHECK OPTION
-- 视图不可更新
-- 物化视图有生命周期限制（LIFECYCLE）
-- 物化视图支持自动查询改写
-- MaxCompute 是批处理引擎，视图在查询时展开执行
