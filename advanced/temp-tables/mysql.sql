-- MySQL: 临时表与临时存储
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TEMPORARY TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-temporary-table.html
--   [2] MySQL 8.0 Reference Manual - Internal Temporary Tables
--       https://dev.mysql.com/doc/refman/8.0/en/internal-temporary-tables.html

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

-- 创建临时表（会话级别，会话结束时自动删除）
CREATE TEMPORARY TABLE temp_active_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200),
    INDEX idx_username (username)
);

-- 从查询创建临时表
CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- 使用 LIKE 复制表结构
CREATE TEMPORARY TABLE temp_users LIKE users;

-- ============================================================
-- 使用临时表
-- ============================================================

INSERT INTO temp_active_users
SELECT id, username, email FROM users WHERE status = 1;

SELECT * FROM temp_active_users WHERE username LIKE 'a%';

UPDATE temp_active_users SET username = UPPER(username);

DELETE FROM temp_active_users WHERE id < 100;

-- ============================================================
-- 临时表特性
-- ============================================================

-- 1. 只对当前会话可见
-- 2. 会话结束时自动删除
-- 3. 可以与普通表同名（临时表优先）
-- 4. 不同会话可以创建同名临时表
-- 5. 不支持外键约束
-- 6. 可以创建索引

-- 显式删除临时表
DROP TEMPORARY TABLE IF EXISTS temp_active_users;

-- 注意：DROP TEMPORARY TABLE 只删除临时表
-- 如果用 DROP TABLE 可能误删同名普通表

-- ============================================================
-- 临时表存储引擎
-- ============================================================

-- 使用 InnoDB 引擎（8.0 默认）
CREATE TEMPORARY TABLE temp_data (
    id INT PRIMARY KEY,
    value TEXT
) ENGINE=InnoDB;

-- 使用 MEMORY 引擎（纯内存，更快但有限制）
CREATE TEMPORARY TABLE temp_cache (
    id INT PRIMARY KEY,
    value VARCHAR(500)
) ENGINE=MEMORY;

-- MEMORY 引擎限制：
-- 不支持 BLOB/TEXT 列
-- 不支持变长行
-- 大小受 max_heap_table_size 限制
-- 重启后丢失

-- 8.0+: 内部临时表使用 TempTable 引擎
-- 控制参数：
-- internal_tmp_mem_storage_engine = TempTable  -- 默认
-- temptable_max_ram = 1G                       -- 内存限制

-- ============================================================
-- CTE 作为临时存储（8.0+）
-- ============================================================

WITH monthly_stats AS (
    SELECT user_id,
           DATE_FORMAT(order_date, '%Y-%m') AS month,
           SUM(amount) AS total
    FROM orders
    GROUP BY user_id, DATE_FORMAT(order_date, '%Y-%m')
)
SELECT user_id, month, total,
       AVG(total) OVER (PARTITION BY user_id ORDER BY month
                        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg
FROM monthly_stats;

-- 递归 CTE
WITH RECURSIVE numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM numbers WHERE n < 100
)
SELECT * FROM numbers;

-- ============================================================
-- 派生表（子查询作为临时表）
-- ============================================================

SELECT u.username, t.total_amount
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total_amount
    FROM orders GROUP BY user_id
) t ON u.id = t.user_id
WHERE t.total_amount > 1000;

-- ============================================================
-- 内部临时表（MySQL 自动创建）
-- ============================================================

-- MySQL 在以下情况自动创建内部临时表：
-- 1. UNION 查询
-- 2. GROUP BY 和 ORDER BY 使用不同列
-- 3. DISTINCT + ORDER BY
-- 4. 派生表（FROM 子查询）
-- 5. 子查询或半连接

-- 查看是否使用了临时表
EXPLAIN SELECT DISTINCT username FROM users ORDER BY age;
-- Extra: Using temporary; Using filesort

-- 控制内部临时表大小
SET tmp_table_size = 67108864;        -- 64MB
SET max_heap_table_size = 67108864;

-- ============================================================
-- 临时表在复制中的注意事项
-- ============================================================

-- 基于语句的复制（SBR）：临时表会被复制
-- 基于行的复制（RBR）：临时表不被复制
-- 混合复制：取决于具体语句

-- 注意：MySQL 只支持会话级临时表，没有全局临时表
-- 注意：DROP TEMPORARY TABLE 是安全的删除方式
-- 注意：8.0+ 的 TempTable 引擎比 MEMORY 引擎更高效
-- 注意：CTE（8.0+）可以替代很多临时表使用场景
-- 注意：MEMORY 引擎临时表不支持 BLOB/TEXT 类型
-- 注意：同名临时表会遮蔽普通表
