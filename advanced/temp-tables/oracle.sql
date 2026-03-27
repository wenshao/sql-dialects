-- Oracle: 临时表与临时存储
--
-- 参考资料:
--   [1] Oracle Documentation - Global Temporary Tables
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html
--   [2] Oracle Documentation - Private Temporary Tables (18c+)
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html

-- ============================================================
-- 全局临时表（Global Temporary Table）
-- ============================================================

-- 事务级临时表（事务提交时清空数据）
CREATE GLOBAL TEMPORARY TABLE gtt_session_calc (
    calc_id   NUMBER,
    user_id   NUMBER,
    amount    NUMBER(10,2),
    calc_date DATE
) ON COMMIT DELETE ROWS;

-- 会话级临时表（会话结束时清空数据）
CREATE GLOBAL TEMPORARY TABLE gtt_user_cache (
    user_id   NUMBER,
    username  VARCHAR2(100),
    email     VARCHAR2(200)
) ON COMMIT PRESERVE ROWS;

-- 注意：表结构是永久的（对所有会话可见），但数据对各会话隔离

-- ============================================================
-- 使用全局临时表
-- ============================================================

-- 插入数据
INSERT INTO gtt_user_cache
SELECT id, username, email FROM users WHERE status = 1;

-- 查询（只能看到当前会话的数据）
SELECT * FROM gtt_user_cache;

-- 可以创建索引（索引也是临时的）
CREATE INDEX idx_gtt_user ON gtt_user_cache(user_id);

-- 可以收集统计信息
-- DBMS_STATS.GATHER_TABLE_STATS 对 GTT 不太有效
-- 使用 ON COMMIT 选项或设置默认统计
EXEC DBMS_STATS.SET_TABLE_STATS('SCHEMA', 'GTT_USER_CACHE', numrows => 10000);

-- ============================================================
-- 私有临时表（18c+）
-- ============================================================

-- 私有临时表：表结构也是临时的（只在当前会话存在）
CREATE PRIVATE TEMPORARY TABLE ora$ptt_results (
    id    NUMBER,
    value NUMBER
) ON COMMIT PRESERVE ROWS;

-- 注意：私有临时表名称必须以 ORA$PTT_ 前缀开头

-- 事务级
CREATE PRIVATE TEMPORARY TABLE ora$ptt_calc (
    id NUMBER, result NUMBER
) ON COMMIT DROP DEFINITION;  -- 事务提交时删除表结构

-- 不记录 redo/undo 日志，性能更好
INSERT INTO ora$ptt_results VALUES (1, 100);
SELECT * FROM ora$ptt_results;

DROP TABLE ora$ptt_results;

-- ============================================================
-- CTE（公共表表达式）
-- ============================================================

WITH monthly_sales AS (
    SELECT user_id,
           TRUNC(order_date, 'MM') AS month,
           SUM(amount) AS total
    FROM orders
    GROUP BY user_id, TRUNC(order_date, 'MM')
)
SELECT user_id, month, total,
       LAG(total) OVER (PARTITION BY user_id ORDER BY month) AS prev_month
FROM monthly_sales;

-- 递归 CTE（11gR2+）
WITH tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 1 FROM departments WHERE parent_id IS NULL
    UNION ALL
    SELECT d.id, d.name, d.parent_id, t.lvl + 1
    FROM departments d JOIN tree t ON d.parent_id = t.id
)
SELECT * FROM tree ORDER BY lvl, name;

-- Oracle 传统层次查询（CONNECT BY）
SELECT id, name, LEVEL AS lvl,
       SYS_CONNECT_BY_PATH(name, '/') AS path
FROM departments
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER SIBLINGS BY name;

-- ============================================================
-- 子查询分解（WITH 物化）
-- ============================================================

-- Oracle 可以自动决定是否物化 CTE
-- 使用 Hint 控制：
WITH /*+ MATERIALIZE */ expensive_calc AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM expensive_calc WHERE total > 1000;

WITH /*+ INLINE */ cheap_calc AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM cheap_calc WHERE age > 25;

-- ============================================================
-- PL/SQL 集合（内存表替代）
-- ============================================================

-- PL/SQL 中使用集合类型代替临时表
DECLARE
    TYPE t_user_rec IS RECORD (id NUMBER, username VARCHAR2(100));
    TYPE t_user_tab IS TABLE OF t_user_rec INDEX BY PLS_INTEGER;
    v_users t_user_tab;
BEGIN
    SELECT id, username BULK COLLECT INTO v_users
    FROM users WHERE status = 1;

    FOR i IN 1..v_users.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(v_users(i).username);
    END LOOP;
END;
/

-- ============================================================
-- 临时表空间
-- ============================================================

-- 查看临时表空间使用
SELECT tablespace_name, bytes_used, bytes_free
FROM v$temp_space_header;

-- 查看当前会话的临时空间使用
SELECT username, segtype, blocks
FROM v$tempseg_usage
WHERE username = USER;

-- 注意：Oracle GTT 的表结构是永久的，数据是临时的
-- 注意：18c+ 的私有临时表（ORA$PTT_）表结构也是临时的
-- 注意：GTT 不记录 redo 日志（仅记录 undo），性能好于普通表
-- 注意：私有临时表完全不记录 redo/undo，性能最好
-- 注意：PL/SQL 集合类型可以替代小型临时表
-- 注意：CONNECT BY 是 Oracle 特有的层次查询语法
