-- Trino (formerly Presto SQL): Views
--
-- 参考资料:
--   [1] Trino Documentation - CREATE VIEW
--       https://trino.io/docs/current/sql/create-view.html
--   [2] Trino Documentation - CREATE MATERIALIZED VIEW
--       https://trino.io/docs/current/sql/create-materialized-view.html
--   [3] Trino Documentation - SQL Statement Syntax
--       https://trino.io/docs/current/sql.html

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

-- 带安全设置
CREATE VIEW active_users
SECURITY DEFINER                            -- DEFINER | INVOKER
AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 带注释
COMMENT ON VIEW active_users IS 'Users who are 18 or older';

-- ============================================
-- 物化视图 (Connector 依赖)
-- 部分 Connector 支持物化视图（如 Iceberg）
-- ============================================
-- Iceberg Connector:
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_order_summary;

-- 物化视图的支持取决于底层 Connector：
-- Iceberg：支持
-- Hive：不支持
-- 其他 Connector：视具体实现

-- ============================================
-- 可更新视图
-- Trino 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- 限制：
-- 不支持 WITH CHECK OPTION
-- 视图不可更新
-- 物化视图支持取决于 Connector
-- Trino 是联邦查询引擎，视图可以跨数据源
-- 视图存储在 Catalog 中
