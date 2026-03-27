-- Hologres: 临时表与临时存储
--
-- 参考资料:
--   [1] Hologres 兼容 PostgreSQL 语法
--       https://help.aliyun.com/document_detail/321181.html

-- ============================================================
-- CREATE TEMPORARY TABLE（兼容 PostgreSQL）
-- ============================================================

CREATE TEMP TABLE temp_users (
    id BIGINT, username TEXT, email TEXT
);

CREATE TEMP TABLE temp_stats AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- ============================================================
-- CTE
-- ============================================================

WITH active AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, COUNT(o.id) AS cnt
FROM active u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- 注意：Hologres 兼容 PostgreSQL 临时表语法
-- 注意：临时表在会话结束时自动删除
-- 注意：CTE 是推荐的中间数据组织方式
