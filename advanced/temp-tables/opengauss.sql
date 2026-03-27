-- openGauss: 临时表与临时存储
--
-- 参考资料:
--   [1] openGauss Documentation - CREATE TABLE
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/CREATE-TABLE.html

-- ============================================================
-- CREATE TEMPORARY TABLE（兼容 PostgreSQL）
-- ============================================================

CREATE TEMP TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- ON COMMIT 行为
CREATE TEMP TABLE temp_tx (id INT, val INT) ON COMMIT DELETE ROWS;
CREATE TEMP TABLE temp_session (id INT, val INT) ON COMMIT PRESERVE ROWS;

-- ============================================================
-- 全局临时表
-- ============================================================

CREATE GLOBAL TEMPORARY TABLE gtt_data (
    id BIGINT, value NUMERIC
) ON COMMIT PRESERVE ROWS;

-- ============================================================
-- UNLOGGED 表
-- ============================================================

CREATE UNLOGGED TABLE staging_data (id BIGINT, data TEXT);

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- 注意：openGauss 基于 PostgreSQL，临时表语法兼容
-- 注意：同时支持 LOCAL TEMPORARY 和 GLOBAL TEMPORARY
-- 注意：支持 UNLOGGED 表用于中间数据
