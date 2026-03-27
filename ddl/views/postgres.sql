-- PostgreSQL: Views
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE VIEW
--       https://www.postgresql.org/docs/current/sql-createview.html
--   [2] PostgreSQL Documentation - CREATE MATERIALIZED VIEW
--       https://www.postgresql.org/docs/current/sql-creatematerializedview.html
--   [3] PostgreSQL Documentation - Updatable Views
--       https://www.postgresql.org/docs/current/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS

-- ============================================
-- 基本视图
-- ============================================
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- CREATE OR REPLACE VIEW
CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- 临时视图
CREATE TEMPORARY VIEW temp_active_users AS
SELECT id, username, email
FROM users
WHERE age >= 18;

-- 递归视图（9.3+）
CREATE RECURSIVE VIEW employee_hierarchy (id, name, manager_id, level) AS
    SELECT id, name, manager_id, 1
    FROM employees
    WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, eh.level + 1
    FROM employees e
    JOIN employee_hierarchy eh ON e.manager_id = eh.id;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION（9.3+ / 9.4+）
-- PostgreSQL 自动支持简单单表视图的 DML
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;                          -- 9.4+

-- WITH LOCAL CHECK OPTION / WITH CASCADED CHECK OPTION（默认）
CREATE VIEW premium_users AS
SELECT id, username, email, age
FROM adult_users
WHERE balance > 1000
WITH CASCADED CHECK OPTION;

-- 通过视图 DML
INSERT INTO adult_users (username, email, age) VALUES ('alice', 'alice@b.com', 25);
UPDATE adult_users SET email = 'new@b.com' WHERE id = 1;
DELETE FROM adult_users WHERE id = 1;

-- 安全屏障视图（Security Barrier，9.2+）
CREATE VIEW secure_users WITH (security_barrier = true) AS
SELECT id, username, email
FROM users
WHERE department = current_setting('app.department');

-- ============================================
-- 物化视图 (Materialized View, 9.3+)
-- ============================================
CREATE MATERIALIZED VIEW mv_order_summary AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 不填充数据创建
CREATE MATERIALIZED VIEW mv_empty AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id
WITH NO DATA;

-- 手动刷新（全量）
REFRESH MATERIALIZED VIEW mv_order_summary;

-- 并发刷新（不阻塞读取，9.4+）
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary;
-- 注意：需要 UNIQUE 索引

-- 在物化视图上创建索引
CREATE UNIQUE INDEX idx_mv_user ON mv_order_summary (user_id);
CREATE INDEX idx_mv_total ON mv_order_summary (total_amount);

-- PostgreSQL 不支持自动刷新，可用 pg_cron 等扩展定时刷新
-- SELECT cron.schedule('refresh_mv', '*/30 * * * *',
--     'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_order_summary');

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP VIEW active_users CASCADE;               -- 级联删除依赖对象

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW IF EXISTS mv_order_summary;

-- 限制：
-- 物化视图不支持自动刷新（需要 pg_cron 或外部调度）
-- CONCURRENTLY 刷新需要 UNIQUE 索引
-- WITH CHECK OPTION 需要 9.4+
-- 复杂视图（JOIN、聚合等）自动可更新性有限，可用 INSTEAD OF 触发器
