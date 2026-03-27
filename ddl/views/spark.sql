-- Spark SQL: Views
--
-- 参考资料:
--   [1] Spark SQL Documentation - CREATE VIEW
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-view.html
--   [2] Spark SQL Documentation - Temporary Views
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-view.html#create-temporary-view

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

-- 临时视图（当前 SparkSession）
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

-- 全局临时视图（所有 SparkSession 可见）
CREATE GLOBAL TEMPORARY VIEW global_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;
-- 访问: SELECT * FROM global_temp.global_active_users;

-- 带列注释
CREATE VIEW order_summary (
    user_id COMMENT 'User identifier',
    order_count COMMENT 'Total orders',
    total_amount COMMENT 'Sum of amounts'
) AS
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

-- 带表属性
CREATE VIEW tagged_view
TBLPROPERTIES ('creator' = 'admin')
AS
SELECT * FROM users;

-- ============================================
-- 物化视图
-- Spark SQL 不支持物化视图
-- ============================================
-- 替代方案：
-- 1. 使用 CACHE TABLE（内存缓存）
CACHE TABLE cached_users AS
SELECT id, username, email FROM users WHERE age >= 18;

-- 带存储级别
CACHE LAZY TABLE cached_orders AS
SELECT * FROM orders;

-- 清除缓存
UNCACHE TABLE cached_users;

-- 2. 使用 CREATE TABLE AS SELECT（持久化）
CREATE TABLE mv_order_summary USING DELTA AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- ============================================
-- 可更新视图
-- Spark SQL 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP GLOBAL TEMPORARY VIEW global_active_users;

-- 限制：
-- 不支持物化视图（使用 CACHE TABLE 或 CTAS 替代）
-- 不支持 WITH CHECK OPTION
-- 视图不可更新
-- 全局临时视图需通过 global_temp schema 访问
