-- TiDB: 临时表与临时存储
--
-- 参考资料:
--   [1] TiDB Documentation - Temporary Tables
--       https://docs.pingcap.com/tidb/stable/temporary-tables
--   [2] TiDB Documentation - CTE
--       https://docs.pingcap.com/tidb/stable/sql-statement-with

-- ============================================================
-- 本地临时表（5.3+）
-- ============================================================

CREATE TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
);

CREATE TEMPORARY TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;

-- 会话结束时自动删除

-- ============================================================
-- 全局临时表（5.3+）
-- ============================================================

-- 结构永久，数据事务级别
CREATE GLOBAL TEMPORARY TABLE gtt_results (
    id BIGINT,
    value DECIMAL(10,2)
) ON COMMIT DELETE ROWS;

-- 事务内使用
BEGIN;
INSERT INTO gtt_results VALUES (1, 100.00);
SELECT * FROM gtt_results;  -- 可以看到数据
COMMIT;
SELECT * FROM gtt_results;  -- 数据已清空

-- ============================================================
-- CTE（5.1+）
-- ============================================================

WITH stats AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id
WHERE s.total > 1000;

-- 递归 CTE（5.1+）
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.level + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree;

-- 注意：TiDB 5.3+ 支持本地临时表和全局临时表
-- 注意：本地临时表是会话级别，全局临时表是事务级别
-- 注意：全局临时表的结构是永久的，数据在事务提交时清空
-- 注意：CTE 从 5.1 版本开始支持
-- 注意：临时表数据不会复制到 TiKV（存储在 TiDB 内存中）
