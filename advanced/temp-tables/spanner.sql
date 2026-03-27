-- Google Cloud Spanner: 临时表与临时存储
--
-- 参考资料:
--   [1] Spanner Documentation - Data Manipulation Language
--       https://cloud.google.com/spanner/docs/dml-tasks
--   [2] Spanner Documentation - Subqueries
--       https://cloud.google.com/spanner/docs/subqueries

-- Spanner 不支持 CREATE TEMPORARY TABLE
-- 使用 CTE、子查询或应用层替代

-- ============================================================
-- CTE（推荐替代方式）
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT u.id, u.username,
           COUNT(o.id) AS order_count,
           SUM(o.amount) AS total_amount
    FROM active_users u
    LEFT JOIN orders o ON u.id = o.user_id
    GROUP BY u.id, u.username
)
SELECT * FROM user_orders WHERE order_count > 5;

-- ============================================================
-- 子查询
-- ============================================================

SELECT u.username, t.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) t ON u.id = t.user_id
WHERE t.total > 1000;

-- ============================================================
-- STRUCT 和 ARRAY（内联临时数据）
-- ============================================================

-- 使用 UNNEST 创建内联临时数据
SELECT * FROM UNNEST(ARRAY<STRUCT<id INT64, name STRING>>[
    STRUCT(1, 'alice'),
    STRUCT(2, 'bob'),
    STRUCT(3, 'charlie')
]) AS temp_data;

-- ============================================================
-- 批处理 DML（应用层临时存储）
-- ============================================================

-- 在应用层使用批处理替代临时表
-- 1. 查询数据到应用内存
-- 2. 在应用层处理
-- 3. 批量写回

-- ============================================================
-- Staging 表（替代方案）
-- ============================================================

-- 创建永久的 Staging 表用于中间处理
CREATE TABLE staging_data (
    batch_id STRING(36),
    id INT64,
    data STRING(MAX),
    created_at TIMESTAMP
) PRIMARY KEY (batch_id, id);

-- 使用后清理
DELETE FROM staging_data WHERE batch_id = 'batch-123';

-- 注意：Spanner 不支持临时表
-- 注意：CTE 是最常用的临时数据组织方式
-- 注意：UNNEST + ARRAY<STRUCT> 可以创建内联临时数据
-- 注意：复杂场景建议在应用层处理中间数据
-- 注意：可以使用永久的 Staging 表替代临时表
