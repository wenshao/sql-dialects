-- Impala: Views
--
-- 参考资料:
--   [1] Impala Documentation - CREATE VIEW
--       https://impala.apache.org/docs/build/html/topics/impala_create_view.html
--   [2] Impala Documentation - ALTER VIEW
--       https://impala.apache.org/docs/build/html/topics/impala_alter_view.html

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- IF NOT EXISTS
CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 修改视图
ALTER VIEW active_users AS
SELECT id, username, email, created_at, age
FROM users
WHERE age >= 18;

-- 重命名视图
ALTER VIEW active_users RENAME TO active_users_v2;

-- 设置视图所有者
ALTER VIEW active_users SET OWNER USER admin_user;

-- ============================================
-- 物化视图
-- Impala 不支持物化视图
-- ============================================
-- 替代方案：
-- 1. 使用 CREATE TABLE AS SELECT (CTAS)
CREATE TABLE mv_order_summary
STORED AS PARQUET
AS SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 2. 使用 INSERT OVERWRITE 刷新
INSERT OVERWRITE TABLE mv_order_summary
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 3. 使用 COMPUTE STATS 优化查询性能
COMPUTE STATS mv_order_summary;

-- ============================================
-- 可更新视图
-- Impala 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

-- 限制：
-- 不支持 CREATE OR REPLACE VIEW（使用 ALTER VIEW 或 DROP + CREATE）
-- 不支持物化视图
-- 不支持 WITH CHECK OPTION
-- 不支持可更新视图
-- 视图不支持 INSERT/UPDATE/DELETE
