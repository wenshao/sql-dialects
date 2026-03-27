-- Snowflake: 临时表与临时存储
--
-- 参考资料:
--   [1] Snowflake Documentation - Temporary and Transient Tables
--       https://docs.snowflake.com/en/user-guide/tables-temp-transient
--   [2] Snowflake Documentation - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table

-- ============================================================
-- 临时表（Temporary Table）
-- ============================================================

-- 创建临时表（会话级别）
CREATE TEMPORARY TABLE temp_users (
    id NUMBER,
    username VARCHAR(100),
    email VARCHAR(200)
);

-- 简写
CREATE TEMP TABLE temp_results (
    id NUMBER,
    value NUMBER
);

-- 从查询创建
CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- 临时表特性：
-- 1. 只对创建它的会话可见
-- 2. 会话结束时自动删除
-- 3. 没有 Fail-safe 保护（不占用存储费用）
-- 4. 没有 Time Travel（默认，可以设置最多 1 天）

-- ============================================================
-- Transient 表（瞬态表）
-- ============================================================

-- 介于临时表和永久表之间
CREATE TRANSIENT TABLE staging_data (
    id NUMBER,
    data VARIANT
);

-- Transient 表特性：
-- 1. 对所有用户可见（如普通表）
-- 2. 持久化存储
-- 3. 没有 Fail-safe（比永久表便宜）
-- 4. Time Travel 最多 1 天
-- 适合 ETL 中间表、staging 数据

-- ============================================================
-- 从查询创建（CTAS）
-- ============================================================

CREATE TEMPORARY TABLE temp_active AS
SELECT * FROM users WHERE status = 1;

CREATE OR REPLACE TEMPORARY TABLE temp_stats AS
SELECT user_id, SUM(amount) AS total
FROM orders GROUP BY user_id;

-- ============================================================
-- CTE（公共表表达式）
-- ============================================================

WITH monthly_stats AS (
    SELECT user_id,
           DATE_TRUNC('month', order_date) AS month,
           SUM(amount) AS total
    FROM orders
    GROUP BY user_id, DATE_TRUNC('month', order_date)
)
SELECT u.username, m.month, m.total
FROM users u JOIN monthly_stats m ON u.id = m.user_id
WHERE m.total > 1000
ORDER BY m.month;

-- 递归 CTE
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, t.level + 1
    FROM categories c JOIN tree t ON c.parent_id = t.id
)
SELECT * FROM tree;

-- ============================================================
-- RESULT_SCAN（查询结果作为临时数据）
-- ============================================================

-- 查看最后一次查询的结果
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 通过 Query ID 获取历史查询结果
SELECT * FROM TABLE(RESULT_SCAN('query-id-here'));

-- 将结果保存到临时表
CREATE TEMPORARY TABLE saved_results AS
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================
-- Stage（暂存区）作为临时存储
-- ============================================================

-- 创建临时 Stage
CREATE TEMPORARY STAGE temp_stage;

-- 将查询结果导出到 Stage
COPY INTO @temp_stage/results
FROM (SELECT * FROM users WHERE status = 1)
FILE_FORMAT = (TYPE = 'CSV');

-- 从 Stage 读回
SELECT $1, $2, $3 FROM @temp_stage/results
(FILE_FORMAT => (TYPE = 'CSV'));

-- ============================================================
-- 临时表与存储成本
-- ============================================================

-- 永久表：Time Travel (0-90天) + Fail-safe (7天)
-- Transient 表：Time Travel (0-1天)，无 Fail-safe
-- 临时表：Time Travel (0-1天)，无 Fail-safe，会话结束后删除

-- 设置临时表的 Time Travel
CREATE TEMPORARY TABLE temp_with_travel (
    id NUMBER, data VARCHAR
) DATA_RETENTION_TIME_IN_DAYS = 1;

-- 注意：Snowflake 同时支持 TEMPORARY 和 TRANSIENT 表
-- 注意：TEMPORARY 表会话级别，TRANSIENT 表持久但无 Fail-safe
-- 注意：RESULT_SCAN 可以引用之前查询的结果（无需临时表）
-- 注意：临时表没有 Fail-safe，存储成本更低
-- 注意：Stage 可以作为文件级别的临时存储
-- 注意：CREATE OR REPLACE 简化了临时表的重建
