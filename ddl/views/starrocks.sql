-- StarRocks: Views
--
-- 参考资料:
--   [1] StarRocks Documentation - CREATE VIEW
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-definition/CREATE_VIEW/
--   [2] StarRocks Documentation - Materialized View
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-definition/CREATE_MATERIALIZED_VIEW/
--   [3] StarRocks Documentation - Async Materialized View
--       https://docs.starrocks.io/docs/using_starrocks/Materialized_view/

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW（StarRocks 3.0+）
-- ALTER VIEW active_users AS ...  （早期版本用 ALTER）

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 同步物化视图 (Sync Materialized View / Rollup)
-- 绑定到单表，自动同步
-- ============================================
CREATE MATERIALIZED VIEW mv_order_agg AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM orders
GROUP BY user_id;

-- 同步物化视图特性：
-- 1. 自动增量更新
-- 2. 查询透明改写
-- 3. 仅支持单表聚合

-- ============================================
-- 异步物化视图 (Async Materialized View, StarRocks 2.5+)
-- 支持多表 JOIN，定时刷新
-- ============================================
CREATE MATERIALIZED VIEW mv_order_detail
DISTRIBUTED BY HASH(user_id) BUCKETS 8
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)       -- 每小时刷新
AS
SELECT o.user_id, u.username, SUM(o.amount) AS total
FROM orders o
JOIN users u ON o.user_id = u.id
GROUP BY o.user_id, u.username;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_order_detail;

-- REFRESH MANUAL（仅手动刷新）
CREATE MATERIALIZED VIEW mv_manual
DISTRIBUTED BY HASH(user_id) BUCKETS 8
REFRESH MANUAL
AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- 查看物化视图状态
-- SHOW MATERIALIZED VIEWS;

-- ============================================
-- 可更新视图
-- StarRocks 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_agg ON orders;        -- 同步
DROP MATERIALIZED VIEW mv_order_detail;                -- 异步

-- 限制：
-- 不支持 WITH CHECK OPTION
-- 同步物化视图仅支持单表
-- 异步物化视图需要 StarRocks 2.5+
-- 异步物化视图的自动刷新基于定时任务
