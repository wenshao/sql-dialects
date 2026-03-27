-- TDSQL: 临时表与临时存储
--
-- 参考资料:
--   [1] TDSQL Documentation
--       https://cloud.tencent.com/document/product/557

-- ============================================================
-- CREATE TEMPORARY TABLE（兼容 MySQL）
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
DROP TEMPORARY TABLE IF EXISTS temp_users;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM stats WHERE total > 1000;

-- ============================================================
-- 分布式注意事项
-- ============================================================

-- TDSQL 分布式版中，临时表存储在当前连接的 proxy 节点
-- 不会分布到后端的 set 节点

-- 注意：TDSQL 兼容 MySQL 临时表语法
-- 注意：分布式版临时表只在 proxy 节点本地
-- 注意：大数据量建议使用分布式的 Staging 表
