-- Flink SQL: 临时表与临时存储
--
-- 参考资料:
--   [1] Flink Documentation - CREATE TABLE
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/
--   [2] Flink Documentation - Temporary Tables
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/common/#temporary-vs-permanent-tables

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

-- 临时表（会话级别）
CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username STRING, email STRING
) WITH (
    'connector' = 'filesystem',
    'path' = '/tmp/temp_users',
    'format' = 'csv'
);

-- 注意：Flink 的临时表需要指定 connector

-- ============================================================
-- CREATE TEMPORARY VIEW（更常用）
-- ============================================================

CREATE TEMPORARY VIEW temp_active_users AS
SELECT * FROM users WHERE status = 1;

CREATE TEMPORARY VIEW temp_orders AS
SELECT user_id, SUM(amount) AS total
FROM orders
GROUP BY user_id;

-- ============================================================
-- 使用临时视图
-- ============================================================

SELECT u.username, t.total
FROM temp_active_users u
JOIN temp_orders t ON u.id = t.user_id;

-- 删除
DROP TEMPORARY VIEW IF EXISTS temp_active_users;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id
)
SELECT u.username, s.cnt FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- 内联表（VALUES）
-- ============================================================

CREATE TEMPORARY VIEW config AS
SELECT * FROM (VALUES ('key1', 'val1'), ('key2', 'val2'))
AS t(key_name, key_value);

-- 注意：Flink 的临时表需要 connector 配置
-- 注意：临时视图是更常用和简便的临时数据方式
-- 注意：临时对象在会话结束时自动删除
-- 注意：CTE 可以组织复杂的流处理逻辑
