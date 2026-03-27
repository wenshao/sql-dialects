-- MariaDB: 临时表与临时存储
--
-- 参考资料:
--   [1] MariaDB Documentation - CREATE TEMPORARY TABLE
--       https://mariadb.com/kb/en/create-table/#temporary-tables
--   [2] MariaDB Documentation - Internal Temporary Tables
--       https://mariadb.com/kb/en/internal-temporary-tables/

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200),
    INDEX idx_username (username)
);

-- 从查询创建
CREATE TEMPORARY TABLE temp_stats AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 使用 LIKE
CREATE TEMPORARY TABLE temp_users_copy LIKE users;

-- 使用 OR REPLACE（MariaDB 10.0.4+）
CREATE OR REPLACE TEMPORARY TABLE temp_data (
    id INT, value TEXT
);

-- ============================================================
-- 使用临时表
-- ============================================================

INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;

-- 显式删除
DROP TEMPORARY TABLE IF EXISTS temp_users;

-- ============================================================
-- MEMORY 引擎（内存表）
-- ============================================================

CREATE TEMPORARY TABLE temp_cache (
    id INT PRIMARY KEY,
    value VARCHAR(500)
) ENGINE=MEMORY;

-- MEMORY 限制：
-- max_heap_table_size 控制大小
-- 不支持 BLOB/TEXT
-- 服务器重启后丢失

-- Aria 引擎（MariaDB 特有，支持崩溃恢复）
CREATE TEMPORARY TABLE temp_aria (
    id INT, data TEXT
) ENGINE=Aria;

-- ============================================================
-- CTE（10.2.1+）
-- ============================================================

WITH monthly AS (
    SELECT user_id, MONTH(order_date) AS m, SUM(amount) AS total
    FROM orders GROUP BY user_id, MONTH(order_date)
)
SELECT * FROM monthly WHERE total > 1000;

-- 递归 CTE
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 100
)
SELECT * FROM nums;

-- ============================================================
-- 序列表生成（MariaDB 10.0+）
-- ============================================================

-- seq 引擎快速生成序列（替代递归 CTE）
SELECT * FROM seq_1_to_100;
SELECT * FROM seq_1_to_1000_step_10;

-- 注意：MariaDB 的 CREATE OR REPLACE TEMPORARY TABLE 简化了重建临时表
-- 注意：Aria 引擎是 MariaDB 特有的临时表引擎，支持更大的数据量
-- 注意：CTE 从 10.2.1 版本开始支持
-- 注意：seq 引擎可以快速生成序列，无需临时表
-- 注意：临时表只对当前会话可见
