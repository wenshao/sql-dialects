-- Spark SQL: 临时表与临时存储
--
-- 参考资料:
--   [1] Spark Documentation - Temporary Views
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-view.html#create-temporary-view
--   [2] Spark Documentation - Cache Table
--       https://spark.apache.org/docs/latest/sql-ref-syntax-aux-cache-cache-table.html

-- ============================================================
-- CREATE TEMPORARY VIEW（推荐）
-- ============================================================

-- Spark SQL 使用临时视图代替临时表
CREATE TEMPORARY VIEW temp_users AS
SELECT * FROM users WHERE status = 1;

CREATE OR REPLACE TEMP VIEW temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 全局临时视图（跨会话，应用级别）
CREATE GLOBAL TEMPORARY VIEW global_stats AS
SELECT COUNT(*) AS total_users FROM users;

-- 访问全局临时视图需要 global_temp 前缀
SELECT * FROM global_temp.global_stats;

-- ============================================================
-- CACHE TABLE（缓存到内存）
-- ============================================================

-- 缓存查询结果到内存
CACHE TABLE cached_users AS
SELECT * FROM users WHERE status = 1;

-- 缓存已有的表/视图
CACHE TABLE users;

-- 惰性缓存（首次访问时缓存）
CACHE LAZY TABLE users;

-- 取消缓存
UNCACHE TABLE cached_users;
UNCACHE TABLE IF EXISTS users;

-- 清除所有缓存
CLEAR CACHE;

-- ============================================================
-- CREATE TABLE（持久化临时结果）
-- ============================================================

-- 使用 CTAS 创建 Delta/Parquet 表
CREATE TABLE staging.temp_results
USING DELTA
AS SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 使用后删除
DROP TABLE staging.temp_results;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- 递归 CTE（3.4+，有限支持）

-- ============================================================
-- DataFrame API（Spark 原生方式）
-- ============================================================

-- 在 Spark 代码中（非 SQL）：
-- df = spark.sql("SELECT * FROM users WHERE status = 1")
-- df.createOrReplaceTempView("temp_users")
-- df.cache()  # 缓存到内存

-- 注意：Spark SQL 使用临时视图而非临时表
-- 注意：CACHE TABLE 将数据缓存到内存中
-- 注意：全局临时视图通过 global_temp schema 访问
-- 注意：CREATE OR REPLACE TEMP VIEW 简化重建
-- 注意：CLEAR CACHE 清除所有缓存的表
