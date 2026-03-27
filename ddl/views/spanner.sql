-- Google Cloud Spanner: Views
--
-- 参考资料:
--   [1] Spanner Documentation - CREATE VIEW
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#create_view
--   [2] Spanner Documentation - Views
--       https://cloud.google.com/spanner/docs/views

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users
SQL SECURITY INVOKER                        -- 必须指定
AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW active_users
SQL SECURITY INVOKER
AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- ============================================
-- 物化视图
-- Spanner 不支持物化视图
-- ============================================
-- 替代方案：
-- 1. 使用二级索引（Spanner 的索引可以包含额外列）
CREATE INDEX idx_users_by_age ON users(age) STORING (username, email);
-- STORING 子句相当于"物化"了部分列

-- 2. 使用交错表（Interleaved Table）
-- Spanner 特有的父子表物理邻近存储

-- 3. 使用 Change Streams + 外部系统维护汇总表

-- ============================================
-- 可更新视图
-- Spanner 视图不可更新
-- ============================================

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;

-- 限制：
-- 必须指定 SQL SECURITY INVOKER
-- 不支持物化视图
-- 不支持 IF NOT EXISTS
-- 不支持 WITH CHECK OPTION
-- 视图不可更新
-- Spanner 使用 STORING 索引和交错表替代部分物化视图场景
