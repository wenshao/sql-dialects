-- Hive: Views
--
-- 参考资料:
--   [1] Hive Language Manual - Views
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-Create/Drop/AlterView
--   [2] Hive Language Manual - Materialized Views
--       https://cwiki.apache.org/confluence/display/Hive/Materialized+views
--   [3] Apache Hive Documentation
--       https://hive.apache.org/

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW（Hive 0.13+）
-- 早期版本需要 DROP + CREATE

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 带列注释的视图
CREATE VIEW order_summary (
    user_id COMMENT 'User identifier',
    order_count COMMENT 'Number of orders',
    total_amount COMMENT 'Total order amount'
) AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 带表属性的视图
CREATE VIEW tagged_view
TBLPROPERTIES ('creator' = 'admin', 'created_date' = '2024-01-01')
AS
SELECT * FROM users WHERE age >= 18;

-- ============================================
-- 物化视图 (Hive 3.0+)
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 禁用自动查询重写
CREATE MATERIALIZED VIEW mv_no_rewrite
DISABLE REWRITE
AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- 手动重建物化视图
ALTER MATERIALIZED VIEW mv_order_summary REBUILD;

-- 启用/禁用查询重写
ALTER MATERIALIZED VIEW mv_order_summary ENABLE REWRITE;
ALTER MATERIALIZED VIEW mv_order_summary DISABLE REWRITE;

-- Hive 物化视图特性：
-- 1. 支持增量重建（仅处理变更数据，基于事务表）
-- 2. 支持自动查询重写（优化器自动使用物化视图）
-- 3. 需要 Hive ACID/事务表作为基表

-- ============================================
-- 可更新视图
-- Hive 视图不可更新（不支持 INSERT/UPDATE/DELETE）
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
-- 物化视图需要 Hive 3.0+ 和事务表（ACID）
-- 物化视图的增量重建依赖基表的事务日志
-- 查询重写需要 CBO（Cost-Based Optimizer）开启
