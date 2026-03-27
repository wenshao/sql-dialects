-- Teradata: 临时表与临时存储
--
-- 参考资料:
--   [1] Teradata Documentation - CREATE TABLE (Temporary)
--       https://docs.teradata.com/r/Teradata-Database-SQL-Data-Definition-Language/June-2017/CREATE-TABLE

-- ============================================================
-- 全局临时表
-- ============================================================

CREATE GLOBAL TEMPORARY TABLE gtt_users (
    id BIGINT, username VARCHAR(100), email VARCHAR(200)
) ON COMMIT PRESERVE ROWS;

-- 事务级
CREATE GLOBAL TEMPORARY TABLE gtt_tx (
    id INTEGER, value DECIMAL(10,2)
) ON COMMIT DELETE ROWS;

-- ============================================================
-- Volatile 表（会话级临时表）
-- ============================================================

-- Volatile 表只在当前会话中存在
CREATE VOLATILE TABLE vt_orders (
    user_id BIGINT, total DECIMAL(10,2), cnt INTEGER
) ON COMMIT PRESERVE ROWS;

-- 从查询创建
CREATE VOLATILE TABLE vt_stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
) WITH DATA ON COMMIT PRESERVE ROWS;

-- Volatile 表特点：
-- 1. 不写入数据字典（更快创建）
-- 2. 会话结束时自动删除
-- 3. 使用 Spool 空间

-- ============================================================
-- Derived Table（派生表）
-- ============================================================

SELECT u.username, t.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) t ON u.id = t.user_id
WHERE t.total > 1000;

-- ============================================================
-- CTE
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;

-- 递归 WITH
WITH RECURSIVE tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 1 FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.lvl + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree;

-- 注意：Teradata 的 Volatile 表比全局临时表创建更快
-- 注意：Volatile 表不写入数据字典
-- 注意：全局临时表的结构是永久的，数据会话隔离
-- 注意：Volatile 表使用会话的 Spool 空间
