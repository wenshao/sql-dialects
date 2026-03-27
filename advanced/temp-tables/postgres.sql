-- PostgreSQL: 临时表与临时存储
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE TABLE (TEMPORARY)
--       https://www.postgresql.org/docs/current/sql-createtable.html
--   [2] PostgreSQL Documentation - WITH Queries (CTE)
--       https://www.postgresql.org/docs/current/queries-with.html

-- ============================================================
-- CREATE TEMPORARY TABLE
-- ============================================================

-- 创建临时表（会话级别）
CREATE TEMPORARY TABLE temp_active_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
);

-- 简写
CREATE TEMP TABLE temp_results (
    id SERIAL,
    value NUMERIC
);

-- 从查询创建
CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY user_id;

-- ============================================================
-- ON COMMIT 行为
-- ============================================================

-- 事务提交时保留数据（默认）
CREATE TEMP TABLE temp_preserve (
    id INT, data TEXT
) ON COMMIT PRESERVE ROWS;

-- 事务提交时删除数据
CREATE TEMP TABLE temp_delete (
    id INT, data TEXT
) ON COMMIT DELETE ROWS;

-- 事务提交时删除表
CREATE TEMP TABLE temp_drop (
    id INT, data TEXT
) ON COMMIT DROP;

-- ============================================================
-- 临时表特性
-- ============================================================

-- 临时表存在于特殊的 pg_temp 模式中
SELECT * FROM pg_temp.temp_active_users;

-- 可以创建索引
CREATE INDEX ON temp_active_users (username);

-- 可以添加约束
ALTER TABLE temp_active_users ADD PRIMARY KEY (id);

-- 检查临时表是否存在
SELECT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE tablename = 'temp_active_users'
    AND schemaname LIKE 'pg_temp%'
);

-- 删除临时表
DROP TABLE IF EXISTS temp_active_users;

-- ============================================================
-- UNLOGGED 表（非临时但高性能）
-- ============================================================

-- 不写 WAL 日志，崩溃后数据丢失，但写入更快
CREATE UNLOGGED TABLE staging_data (
    id BIGINT,
    data JSONB
);

-- 适用场景：导入/ETL 中间表、缓存表

-- ============================================================
-- CTE（公共表表达式）
-- ============================================================

-- 基本 CTE
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, COUNT(o.id) AS order_count
FROM active_users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- 可写 CTE（INSERT/UPDATE/DELETE + RETURNING）
WITH deleted AS (
    DELETE FROM orders WHERE status = 'cancelled' RETURNING *
)
INSERT INTO cancelled_orders SELECT * FROM deleted;

WITH updated AS (
    UPDATE users SET status = 0
    WHERE last_login < NOW() - INTERVAL '1 year'
    RETURNING id, username
)
SELECT * FROM updated;

-- ============================================================
-- CTE 物化控制（12+）
-- ============================================================

-- 强制物化（创建临时结果集）
WITH active AS MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;

-- 禁止物化（内联优化）
WITH active AS NOT MATERIALIZED (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active WHERE age > 25;

-- ============================================================
-- 递归 CTE
-- ============================================================

WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, 0 AS depth,
           ARRAY[id] AS path
    FROM categories WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, t.depth + 1,
           t.path || c.id
    FROM categories c
    JOIN tree t ON c.parent_id = t.id
    WHERE NOT c.id = ANY(t.path)  -- 防止循环
)
SELECT * FROM tree ORDER BY path;

-- ============================================================
-- 临时视图
-- ============================================================

-- 在临时表上创建视图
CREATE TEMP VIEW temp_user_summary AS
SELECT username, email FROM temp_active_users;

-- ============================================================
-- pg_temp schema
-- ============================================================

-- 临时对象自动创建在 pg_temp_N schema 中
-- 每个会话有自己的 pg_temp schema

-- 在函数中使用临时表
CREATE OR REPLACE FUNCTION get_active_user_count()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS _tmp_active
    AS SELECT * FROM users WHERE status = 1;

    SELECT COUNT(*) INTO v_count FROM _tmp_active;
    DROP TABLE _tmp_active;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 注意：PostgreSQL 临时表是会话级别的
-- 注意：ON COMMIT 控制事务结束时的行为
-- 注意：UNLOGGED 表适合不需要持久化的中间数据
-- 注意：12+ 可以用 MATERIALIZED / NOT MATERIALIZED 控制 CTE 物化
-- 注意：可写 CTE（WITH ... DELETE/UPDATE RETURNING）是 PostgreSQL 特色
-- 注意：临时表存在于 pg_temp schema 中
