-- H2 Database: 临时表与临时存储
--
-- 参考资料:
--   [1] H2 Documentation - CREATE TABLE
--       https://h2database.com/html/commands.html#create_table

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

CREATE LOCAL TEMPORARY TABLE temp_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- ON COMMIT 行为
CREATE LOCAL TEMPORARY TABLE temp_tx (id INT, val INT)
ON COMMIT DELETE ROWS;

CREATE LOCAL TEMPORARY TABLE temp_session (id INT, val INT)
ON COMMIT PRESERVE ROWS;  -- 默认

-- 全局临时表
CREATE GLOBAL TEMPORARY TABLE gtt_data (id INT, data VARCHAR)
ON COMMIT PRESERVE ROWS;

-- ============================================================
-- 使用和删除
-- ============================================================

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
DROP TABLE IF EXISTS temp_users;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- 递归 CTE
WITH RECURSIVE nums(n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM nums WHERE n < 100
)
SELECT * FROM nums;

-- 注意：H2 支持 LOCAL TEMPORARY 和 GLOBAL TEMPORARY
-- 注意：ON COMMIT DELETE ROWS / PRESERVE ROWS 控制事务行为
-- 注意：连接关闭时临时表自动删除
-- 注意：H2 支持 CTE 和递归 CTE
