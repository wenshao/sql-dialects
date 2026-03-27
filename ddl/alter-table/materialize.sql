-- Materialize: ALTER TABLE / ALTER SOURCE
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 兼容 PostgreSQL ALTER 语法（部分支持）

-- ============================================================
-- ALTER TABLE
-- ============================================================

-- 添加列
ALTER TABLE users ADD COLUMN phone TEXT;

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- ============================================================
-- ALTER SOURCE
-- ============================================================

-- 重命名 SOURCE
ALTER SOURCE kafka_orders RENAME TO order_stream;

-- ============================================================
-- ALTER MATERIALIZED VIEW
-- ============================================================

-- 重命名物化视图
ALTER MATERIALIZED VIEW order_summary RENAME TO order_stats;

-- ============================================================
-- ALTER VIEW
-- ============================================================

ALTER VIEW active_users RENAME TO verified_users;

-- ============================================================
-- ALTER CONNECTION
-- ============================================================

ALTER CONNECTION kafka_conn RENAME TO kafka_main;

-- ============================================================
-- DROP 操作
-- ============================================================

DROP TABLE IF EXISTS users CASCADE;
DROP SOURCE IF EXISTS kafka_orders CASCADE;
DROP MATERIALIZED VIEW IF EXISTS order_summary;
DROP VIEW IF EXISTS active_users;
DROP CONNECTION IF EXISTS kafka_conn;

-- CASCADE 删除依赖对象
DROP SOURCE kafka_orders CASCADE;    -- 同时删除依赖的视图

-- ============================================================
-- 修改物化视图（需要重建）
-- ============================================================

-- 物化视图不能直接修改，需要 DROP + CREATE
DROP MATERIALIZED VIEW IF EXISTS order_summary;
CREATE MATERIALIZED VIEW order_summary AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount,
       AVG(amount) AS avg_amount       -- 新增列
FROM orders
GROUP BY user_id;

-- 注意：ALTER TABLE 功能有限，不支持修改列类型
-- 注意：MATERIALIZED VIEW 不能直接 ALTER，需要重建
-- 注意：DROP CASCADE 会删除所有依赖对象
-- 注意：SOURCE 一旦创建，schema 不能修改
