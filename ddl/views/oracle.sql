-- Oracle: 视图与物化视图 (Views & Materialized Views)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE VIEW
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-VIEW.html
--   [2] Oracle SQL Language Reference - CREATE MATERIALIZED VIEW
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-MATERIALIZED-VIEW.html

-- ============================================================
-- 1. 基本视图
-- ============================================================

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

-- FORCE（即使基表不存在也创建视图，Oracle 独有）
CREATE OR REPLACE FORCE VIEW future_view AS
SELECT * FROM not_yet_created_table;

-- 只读视图（11g+，Oracle 独有语法）
CREATE VIEW read_only_users AS
SELECT id, username, email
FROM users
WITH READ ONLY;

-- ============================================================
-- 2. 可更新视图与 INSTEAD OF 触发器
-- ============================================================

-- WITH CHECK OPTION（确保通过视图的 DML 满足视图条件）
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users WHERE age >= 18
WITH CHECK OPTION CONSTRAINT chk_adult;

-- INSTEAD OF 触发器使复杂视图可更新（Oracle 独有能力）
CREATE OR REPLACE TRIGGER trg_order_detail_insert
INSTEAD OF INSERT ON order_detail_view
FOR EACH ROW
BEGIN
    INSERT INTO orders (id, amount) VALUES (:NEW.id, :NEW.amount);
END;
/

-- ============================================================
-- 3. 物化视图（Oracle 最强大的特性之一）
-- ============================================================

-- 3.1 完全刷新（最简单）
CREATE MATERIALIZED VIEW mv_order_summary
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders GROUP BY user_id;

-- 3.2 快速刷新（增量刷新，需要物化视图日志）
CREATE MATERIALIZED VIEW LOG ON orders
WITH PRIMARY KEY, ROWID INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW mv_orders_fast
BUILD IMMEDIATE
REFRESH FAST ON COMMIT                    -- 提交时自动刷新
AS
SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total_amount
FROM orders GROUP BY user_id;

-- 3.3 定时自动刷新
CREATE MATERIALIZED VIEW mv_scheduled
BUILD IMMEDIATE
REFRESH COMPLETE
START WITH SYSDATE
NEXT SYSDATE + 1/24                      -- 每小时刷新
AS
SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id;

-- 3.4 查询重写（Query Rewrite，Oracle 杀手级特性）
CREATE MATERIALIZED VIEW mv_with_rewrite
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
ENABLE QUERY REWRITE                     -- 优化器自动使用此物化视图
AS
SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders GROUP BY user_id;

-- 手动刷新
BEGIN
    DBMS_MVIEW.REFRESH('mv_order_summary', 'C');  -- C=Complete, F=Fast, ?=Force
END;
/

-- ============================================================
-- 4. 物化视图设计分析（对引擎开发者的核心价值）
-- ============================================================

-- 4.1 刷新策略对比:
--   COMPLETE: 全量重新计算，简单但慢
--   FAST:     增量刷新，快但有严格限制（需要 MV LOG，查询需满足约束）
--   FORCE:    先尝试 FAST，失败则 COMPLETE
--
-- FAST 刷新限制:
--   - 基表必须有物化视图日志
--   - 聚合查询只支持部分函数（SUM, COUNT, MIN, MAX 等）
--   - JOIN 视图有更严格的约束
--   这些限制源于增量维护的数学可行性（可增量更新的聚合 vs 不可增量更新的聚合）

-- 4.2 Query Rewrite: 透明加速
--   优化器在解析查询时，自动判断是否可以用物化视图替代基表查询。
--   用户不需要修改 SQL，查询自动被重写到物化视图。
--   这是 Oracle 在 OLAP/数据仓库领域的核心竞争力。
--
-- 横向对比:
--   Oracle:     最完善的 Query Rewrite（自动重写，透明加速）
--   PostgreSQL: 无 Query Rewrite（物化视图是手动管理的缓存）
--   MySQL:      不支持物化视图
--   SQL Server: Indexed View（类似，但限制更多）
--   BigQuery:   自动物化视图（Google 自动管理刷新和重写）
--   Snowflake:  自动物化视图（类似 BigQuery）
--   Doris/SR:   同步物化视图 + 自动 Query Rewrite
--
-- 对引擎开发者的启示:
--   物化视图的三个实现层次:
--   Level 1: 手动刷新 + 显式查询（最简单）
--   Level 2: 自动刷新（ON COMMIT / 定时）
--   Level 3: Query Rewrite（优化器自动重写，最复杂但价值最大）
--   OLAP 引擎应该至少实现 Level 2，Level 3 是差异化竞争力。

-- ============================================================
-- 5. '' = NULL 对视图的影响
-- ============================================================

-- 通过视图过滤空字符串的陷阱:
CREATE VIEW non_empty_bio AS
SELECT * FROM users WHERE bio IS NOT NULL;
-- 由于 '' = NULL，这个视图也过滤了 bio = '' 的行
-- 在其他数据库中，bio = '' 的行会保留

-- 正确做法（如果需要保留空串但排除 NULL）:
-- 在 Oracle 中无法区分，因为 '' 就是 NULL

-- ============================================================
-- 6. 删除视图
-- ============================================================
DROP VIEW active_users;
DROP VIEW active_users CASCADE CONSTRAINTS;

DROP MATERIALIZED VIEW mv_order_summary;
DROP MATERIALIZED VIEW LOG ON orders;

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- Oracle 7:   基本视图
-- Oracle 8i:  物化视图（原名 SNAPSHOT）、Query Rewrite
-- Oracle 9i:  FAST 刷新增强
-- Oracle 10g: ON COMMIT 刷新增强
-- Oracle 11g: WITH READ ONLY 语法
-- Oracle 12c: 实时物化视图（ON QUERY COMPUTATION）
-- Oracle 21c: 自动物化视图管理（SYS_AUTO_MV）
