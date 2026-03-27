-- Apache Doris: Views
--
-- 参考资料:
--   [1] Apache Doris Documentation - CREATE VIEW
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-VIEW
--   [2] Apache Doris Documentation - Materialized View
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-MATERIALIZED-VIEW
--   [3] Apache Doris Documentation - Async Materialized View
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-ASYNC-MATERIALIZED-VIEW

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW（Doris 2.0+）
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
-- 同步物化视图 (Rollup / Sync Materialized View)
-- 绑定到单个基表，自动同步更新
-- ============================================
CREATE MATERIALIZED VIEW mv_order_agg AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM orders
GROUP BY user_id;
-- 同步物化视图在数据导入时自动更新
-- 查询优化器自动选择合适的物化视图（透明改写）

-- 查看物化视图状态
-- SHOW ALTER TABLE MATERIALIZED VIEW FROM db_name;

-- ============================================
-- 异步物化视图 (Async Materialized View, Doris 2.1+)
-- 支持多表 JOIN，定时刷新
-- ============================================
CREATE MATERIALIZED VIEW mv_order_detail
BUILD IMMEDIATE                              -- 创建时立即构建
REFRESH AUTO                                 -- 自动刷新（检测基表变更）
ON SCHEDULE EVERY 1 HOUR                     -- 定时刷新间隔
AS
SELECT o.user_id, u.username, SUM(o.amount) AS total
FROM orders o
JOIN users u ON o.user_id = u.id
GROUP BY o.user_id, u.username;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_order_detail;

-- ============================================
-- 可更新视图
-- Doris 视图不可更新
-- ============================================
-- 替代方案：直接操作基表

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_agg ON orders;        -- 同步物化视图
DROP MATERIALIZED VIEW mv_order_detail;                -- 异步物化视图

-- 限制：
-- 不支持 WITH CHECK OPTION
-- 同步物化视图仅支持单表聚合
-- 同步物化视图的聚合函数有限（SUM, MIN, MAX, COUNT, BITMAP_UNION, HLL_UNION）
-- 异步物化视图需要 Doris 2.1+
