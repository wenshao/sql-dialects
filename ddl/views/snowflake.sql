-- Snowflake: Views
--
-- 参考资料:
--   [1] Snowflake Documentation - CREATE VIEW
--       https://docs.snowflake.com/en/sql-reference/sql/create-view
--   [2] Snowflake Documentation - CREATE MATERIALIZED VIEW
--       https://docs.snowflake.com/en/sql-reference/sql/create-materialized-view
--   [3] Snowflake Documentation - Secure Views
--       https://docs.snowflake.com/en/user-guide/views-secure

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

-- 安全视图（Secure View）
-- 隐藏视图定义，防止通过查询计划推断数据
CREATE SECURE VIEW secure_user_data AS
SELECT id, username, email
FROM users
WHERE department = CURRENT_ROLE();

-- 带注释的视图
CREATE VIEW order_summary
COMMENT = 'Order aggregation by user'
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 递归视图（CTE）
CREATE VIEW employee_hierarchy AS
WITH RECURSIVE hierarchy AS (
    SELECT id, name, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, h.level + 1
    FROM employees e JOIN hierarchy h ON e.manager_id = h.id
)
SELECT * FROM hierarchy;

-- ============================================
-- 物化视图 (Materialized View)
-- Snowflake Enterprise Edition+ 支持
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 安全物化视图
CREATE SECURE MATERIALIZED VIEW mv_secure AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- 物化视图特性：
-- 1. Snowflake 自动维护物化视图（增量刷新）
-- 2. 自动查询重写（优化器透明使用）
-- 3. 有额外的存储和计算成本
-- 4. 不需要手动 REFRESH

-- 物化视图限制：
-- 1. 仅支持单表查询（不支持 JOIN）
-- 2. 不支持 UDF
-- 3. 不支持某些聚合函数
-- 4. 不支持 HAVING, ORDER BY, LIMIT
-- 5. 基表必须有聚集键

-- 挂起/恢复物化视图
ALTER MATERIALIZED VIEW mv_order_summary SUSPEND;
ALTER MATERIALIZED VIEW mv_order_summary RESUME;

-- ============================================
-- 可更新视图
-- Snowflake 视图不可更新
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
-- 物化视图仅 Enterprise Edition+
-- 物化视图不支持 JOIN
-- 物化视图自动维护，有存储成本
