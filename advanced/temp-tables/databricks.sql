-- Databricks SQL: 临时表与临时存储
--
-- 参考资料:
--   [1] Databricks Documentation - Temporary Views
--       https://docs.databricks.com/sql/language-manual/sql-ref-syntax-ddl-create-view.html
--   [2] Databricks Documentation - CACHE TABLE
--       https://docs.databricks.com/sql/language-manual/sql-ref-syntax-aux-cache-cache-table.html

-- ============================================================
-- CREATE TEMPORARY VIEW
-- ============================================================

CREATE TEMPORARY VIEW temp_users AS SELECT * FROM users WHERE status = 1;

CREATE OR REPLACE TEMP VIEW temp_stats AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 全局临时视图
CREATE GLOBAL TEMPORARY VIEW global_active_users AS
SELECT * FROM users WHERE status = 1;

SELECT * FROM global_temp.global_active_users;

-- ============================================================
-- CACHE TABLE
-- ============================================================

CACHE TABLE cached_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

CACHE LAZY TABLE users;
UNCACHE TABLE IF EXISTS cached_orders;

-- ============================================================
-- CREATE TABLE（Delta Lake 临时表）
-- ============================================================

CREATE TABLE staging.temp_results USING DELTA AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

DROP TABLE staging.temp_results;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- 注意：Databricks 使用临时视图替代临时表
-- 注意：CACHE TABLE 将数据缓存到集群内存
-- 注意：Delta Lake 表可以作为持久化的 Staging 表
-- 注意：全局临时视图通过 global_temp 前缀访问
