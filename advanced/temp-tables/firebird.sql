-- Firebird: 临时表与临时存储
--
-- 参考资料:
--   [1] Firebird Documentation - Global Temporary Tables
--       https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref40/fblangref40-ddl-table.html#fblangref40-ddl-tbl-gtt

-- ============================================================
-- 全局临时表（2.1+）
-- ============================================================

-- 事务级（事务结束时清空数据）
CREATE GLOBAL TEMPORARY TABLE gtt_tx_data (
    id INTEGER NOT NULL,
    value DOUBLE PRECISION
) ON COMMIT DELETE ROWS;

-- 连接级（连接断开时清空数据）
CREATE GLOBAL TEMPORARY TABLE gtt_conn_data (
    id INTEGER NOT NULL,
    username VARCHAR(100),
    email VARCHAR(200)
) ON COMMIT PRESERVE ROWS;

-- 注意：表结构是永久的，数据对各连接隔离

-- ============================================================
-- 使用全局临时表
-- ============================================================

INSERT INTO gtt_conn_data
SELECT id, username, email FROM users WHERE status = 1;

SELECT * FROM gtt_conn_data;

-- 可以创建索引
CREATE INDEX idx_gtt_user ON gtt_conn_data(username);

-- ============================================================
-- CTE（2.1+）
-- ============================================================

WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, COUNT(o.id) AS order_count
FROM active_users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- 递归 CTE
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 1 AS level
    FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.level + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree;

-- ============================================================
-- EXECUTE BLOCK（匿名 PSQL 块）
-- ============================================================

-- 可以在 PSQL 块中使用变量作为临时存储
EXECUTE BLOCK
RETURNS (username VARCHAR(100), total_amount DOUBLE PRECISION)
AS
BEGIN
    FOR SELECT u.username, SUM(o.amount)
        FROM users u JOIN orders o ON u.id = o.user_id
        GROUP BY u.username
        INTO :username, :total_amount
    DO
    BEGIN
        IF (total_amount > 1000) THEN
            SUSPEND;
    END
END;

-- 注意：Firebird 只有全局临时表（结构永久，数据临时）
-- 注意：没有 CREATE TEMPORARY TABLE（会话级表结构）
-- 注意：ON COMMIT DELETE ROWS 是事务级，ON COMMIT PRESERVE ROWS 是连接级
-- 注意：CTE 从 2.1 版本开始支持
-- 注意：EXECUTE BLOCK 可以使用变量作为简单的临时存储
