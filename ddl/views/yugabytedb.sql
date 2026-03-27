-- YugabyteDB: Views
--
-- 参考资料:
--   [1] YugabyteDB Documentation - CREATE VIEW
--       https://docs.yugabyte.com/latest/api/ysql/the-sql-language/statements/ddl_create_view/
--   [2] YugabyteDB Documentation - CREATE MATERIALIZED VIEW
--       https://docs.yugabyte.com/latest/api/ysql/the-sql-language/statements/ddl_create_matview/
--   [3] YugabyteDB Documentation - Views
--       https://docs.yugabyte.com/latest/explore/ysql-language-features/views/

-- ============================================
-- 基本视图（兼容 PostgreSQL）
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

-- 临时视图
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;

CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH CASCADED CHECK OPTION;

-- ============================================
-- 物化视图
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 手动刷新
REFRESH MATERIALIZED VIEW mv_order_summary;

-- 并发刷新
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;

-- 不填充数据创建
CREATE MATERIALIZED VIEW mv_empty AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
WITH NO DATA;

-- 在物化视图上创建索引
CREATE UNIQUE INDEX idx_mv_user ON mv_order_summary (user_id);

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;
DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- 限制：
-- 物化视图不支持自动刷新（同 PostgreSQL）
-- CONCURRENTLY 需要 UNIQUE 索引
-- YugabyteDB 的 YSQL 兼容 PostgreSQL
-- 分布式环境下物化视图的刷新可能较慢
