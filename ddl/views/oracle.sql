-- Oracle: Views
--
-- 参考资料:
--   [1] Oracle Documentation - CREATE VIEW
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/CREATE-VIEW.html
--   [2] Oracle Documentation - CREATE MATERIALIZED VIEW
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/CREATE-MATERIALIZED-VIEW.html
--   [3] Oracle Documentation - Updatable Views
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/CREATE-VIEW.html#GUID-61D2D2B4-DACC-4C7C-89EB-7E50D9BE4100__BABBAFDE

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

-- FORCE（即使基表不存在也创建）
CREATE OR REPLACE FORCE VIEW future_view AS
SELECT * FROM not_yet_created_table;

-- 只读视图（11g+）
CREATE VIEW read_only_users AS
SELECT id, username, email
FROM users
WITH READ ONLY;

-- ============================================
-- 可更新视图 + WITH CHECK OPTION
-- ============================================
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION CONSTRAINT chk_adult;

-- INSTEAD OF 触发器使复杂视图可更新
CREATE VIEW order_detail AS
SELECT o.id, o.amount, u.username
FROM orders o JOIN users u ON o.user_id = u.id;

CREATE OR REPLACE TRIGGER trg_order_detail_insert
INSTEAD OF INSERT ON order_detail
FOR EACH ROW
BEGIN
    INSERT INTO orders (id, amount) VALUES (:NEW.id, :NEW.amount);
END;
/

-- ============================================
-- 物化视图 (Materialized View)
-- Oracle 是物化视图功能最丰富的数据库
-- ============================================

-- 完全刷新，按需
CREATE MATERIALIZED VIEW mv_order_summary
BUILD IMMEDIATE
REFRESH COMPLETE
ON DEMAND
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 快速刷新（增量刷新，需要物化视图日志）
CREATE MATERIALIZED VIEW LOG ON orders
WITH PRIMARY KEY, ROWID
INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW mv_orders_fast
BUILD IMMEDIATE
REFRESH FAST ON COMMIT                      -- 提交时自动刷新
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 定时自动刷新
CREATE MATERIALIZED VIEW mv_scheduled
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH SYSDATE
NEXT SYSDATE + 1/24                        -- 每小时刷新
AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- REFRESH FORCE（先尝试快速刷新，失败则完全刷新）
CREATE MATERIALIZED VIEW mv_force_refresh
REFRESH FORCE ON DEMAND
AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

-- 查询重写（Query Rewrite）
CREATE MATERIALIZED VIEW mv_with_rewrite
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
ENABLE QUERY REWRITE                       -- 允许优化器自动使用此物化视图
AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders
GROUP BY user_id;

-- 手动刷新
BEGIN
    DBMS_MVIEW.REFRESH('mv_order_summary', 'C');   -- C=Complete, F=Fast, ?=Force
END;
/

-- 在物化视图上创建索引
CREATE INDEX idx_mv_user ON mv_order_summary (user_id);

-- ============================================
-- 删除视图
-- ============================================
DROP VIEW active_users;
DROP VIEW active_users CASCADE CONSTRAINTS;

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW mv_order_summary PRESERVE TABLE;  -- 保留底层表

DROP MATERIALIZED VIEW LOG ON orders;

-- 限制：
-- FORCE 创建的视图在基表不存在时不可查询
-- 快速刷新有较多限制（需要物化视图日志，查询有约束）
-- ON COMMIT 刷新影响 DML 性能
-- ENABLE QUERY REWRITE 需要合适的权限和统计信息
