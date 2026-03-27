-- PolarDB: 临时表与临时存储
--
-- 参考资料:
--   [1] PolarDB MySQL Documentation
--       https://help.aliyun.com/document_detail/316280.html
--   [2] PolarDB PostgreSQL Documentation
--       https://help.aliyun.com/document_detail/172538.html

-- ============================================================
-- PolarDB MySQL 兼容版
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

DROP TEMPORARY TABLE IF EXISTS temp_users;

-- CTE（兼容 MySQL 8.0）
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM stats WHERE total > 1000;

-- ============================================================
-- PolarDB PostgreSQL 兼容版
-- ============================================================

-- CREATE TEMP TABLE temp_data (id INT, val NUMERIC);
-- CREATE TEMP TABLE temp_data ON COMMIT PRESERVE ROWS AS ...;

-- CTE 和可写 CTE 兼容 PostgreSQL

-- 注意：PolarDB 根据兼容模式（MySQL/PostgreSQL）使用不同的临时表语法
-- 注意：临时表对各会话隔离
-- 注意：PolarDB 的共享存储架构对临时表有优化
