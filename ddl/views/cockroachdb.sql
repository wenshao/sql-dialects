-- CockroachDB: Views
--
-- 参考资料:
--   [1] CockroachDB Documentation - CREATE VIEW
--       https://www.cockroachlabs.com/docs/stable/create-view
--   [2] CockroachDB Documentation - Views
--       https://www.cockroachlabs.com/docs/stable/views
--   [3] CockroachDB Documentation - Materialized Views
--       https://www.cockroachlabs.com/docs/stable/create-materialized-view

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW（v22.2+）
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 物化视图 (Materialized View, v21.2+)
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, count(*) AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- IF NOT EXISTS
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_order_summary AS
SELECT user_id, count(*) AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 手动刷新物化视图（CockroachDB 不支持自动刷新）
REFRESH MATERIALIZED VIEW mv_order_summary;

-- 并发刷新（不阻塞读取，v22.1+）
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;
-- 注意：CONCURRENTLY 要求物化视图有 UNIQUE 索引

-- 在物化视图上创建索引
CREATE INDEX idx_mv_user ON mv_order_summary (user_id);

-- ============================================
-- 可更新视图
-- CockroachDB 不支持可更新视图（不能对视图 INSERT/UPDATE/DELETE）
-- ============================================
-- 替代方案：直接操作基表

-- 注意：不支持 WITH CHECK OPTION

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;       -- 级联删除依赖此视图的对象

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- 限制：
-- 物化视图需要手动刷新（REFRESH MATERIALIZED VIEW）
-- 物化视图不支持自动/定时刷新
-- 视图不支持 WITH CHECK OPTION
-- 视图不支持 INSERT/UPDATE/DELETE
