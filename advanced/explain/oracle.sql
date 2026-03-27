-- Oracle: 执行计划与查询分析
--
-- 参考资料:
--   [1] Oracle Documentation - EXPLAIN PLAN
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/EXPLAIN-PLAN.html
--   [2] Oracle Documentation - DBMS_XPLAN
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_XPLAN.html
--   [3] Oracle Documentation - SQL Tuning Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/

-- ============================================================
-- EXPLAIN PLAN 基本用法
-- ============================================================

-- 生成执行计划（存入 PLAN_TABLE）
EXPLAIN PLAN FOR
SELECT * FROM users WHERE username = 'alice';

-- 查看执行计划
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 带语句标识符
EXPLAIN PLAN SET STATEMENT_ID = 'query1' FOR
SELECT * FROM users WHERE age > 25;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'query1', 'ALL'));

-- ============================================================
-- DBMS_XPLAN 显示格式
-- ============================================================

-- BASIC: 最简格式
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'BASIC'));

-- TYPICAL: 默认格式（含成本、行数、字节）
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'TYPICAL'));

-- ALL: 所有信息
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'ALL'));

-- 自定义格式选项
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL,
    'BASIC +COST +ROWS +BYTES +PREDICATE'));

-- ============================================================
-- AUTOTRACE（SQL*Plus / SQLcl）
-- ============================================================

-- 显示执行计划和统计信息（执行查询）
-- SET AUTOTRACE ON

-- 只显示执行计划（不执行）
-- SET AUTOTRACE TRACEONLY EXPLAIN

-- 只显示统计信息
-- SET AUTOTRACE TRACEONLY STATISTICS

-- ============================================================
-- DBMS_XPLAN.DISPLAY_CURSOR（已执行的语句）
-- ============================================================

-- 查看最近执行的语句的实际执行计划
SELECT /*+ GATHER_PLAN_STATISTICS */ *
FROM users WHERE age > 25;

-- 显示实际行数（需要 GATHER_PLAN_STATISTICS 提示）
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

-- 通过 SQL_ID 查看
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('sql_id_here', NULL, 'ALLSTATS'));

-- ============================================================
-- SQL Monitor（实时监控，Enterprise Edition）
-- ============================================================

-- 自动监控长时间运行的查询（>5秒）或并行查询
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id => 'sql_id_here',
    type => 'TEXT'
) FROM dual;

-- HTML 格式报告
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
    sql_id => 'sql_id_here',
    type => 'HTML'
) FROM dual;

-- 查看正在运行的 SQL 监控
SELECT sql_id, status, elapsed_time/1000000 AS seconds,
       cpu_time/1000000 AS cpu_seconds, buffer_gets, disk_reads
FROM v$sql_monitor
WHERE status = 'EXECUTING';

-- ============================================================
-- V$SQL / V$SQL_PLAN（共享池中的执行计划）
-- ============================================================

-- 查看共享池中的执行计划
SELECT sql_id, plan_hash_value, executions, elapsed_time/1000000 AS total_sec,
       buffer_gets, disk_reads, rows_processed
FROM v$sql
WHERE sql_text LIKE '%users%'
ORDER BY elapsed_time DESC;

-- 查看具体执行计划
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('sql_id', 0, 'ALL'));

-- 查看 AWR 中的历史执行计划
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('sql_id'));

-- ============================================================
-- 10046 跟踪（详细诊断）
-- ============================================================

-- 启用 SQL 跟踪
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';

SELECT * FROM users WHERE age > 25;

-- 关闭跟踪
ALTER SESSION SET EVENTS '10046 trace name context off';

-- 使用 DBMS_SESSION
EXEC DBMS_SESSION.SESSION_TRACE_ENABLE(waits => TRUE, binds => TRUE);
-- 执行查询
EXEC DBMS_SESSION.SESSION_TRACE_DISABLE;

-- 使用 tkprof 分析跟踪文件（操作系统命令）：
-- tkprof trace_file.trc output.txt sys=no

-- ============================================================
-- SQL Tuning Advisor（Enterprise Edition）
-- ============================================================

-- 创建调优任务
DECLARE
    l_task_id VARCHAR2(100);
BEGIN
    l_task_id := DBMS_SQLTUNE.CREATE_TUNING_TASK(
        sql_id => 'sql_id_here',
        scope => DBMS_SQLTUNE.SCOPE_COMPREHENSIVE,
        time_limit => 300
    );
    DBMS_SQLTUNE.EXECUTE_TUNING_TASK(l_task_id);
END;
/

-- 查看建议
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('task_name') FROM dual;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- TABLE ACCESS FULL        全表扫描
-- TABLE ACCESS BY INDEX ROWID  通过索引回表
-- INDEX UNIQUE SCAN         唯一索引扫描
-- INDEX RANGE SCAN          索引范围扫描
-- INDEX FULL SCAN           索引全扫描
-- INDEX FAST FULL SCAN      索引快速全扫描
-- NESTED LOOPS              嵌套循环连接
-- HASH JOIN                 哈希连接
-- SORT MERGE JOIN           排序合并连接
-- SORT ORDER BY             排序
-- HASH GROUP BY             哈希分组
-- PARTITION RANGE ALL/SINGLE  分区裁剪

-- ============================================================
-- Hint 控制执行计划
-- ============================================================

EXPLAIN PLAN FOR
SELECT /*+ FULL(u) */ * FROM users u WHERE id = 1;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

EXPLAIN PLAN FOR
SELECT /*+ INDEX(u idx_users_age) */ * FROM users u WHERE age > 25;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

EXPLAIN PLAN FOR
SELECT /*+ USE_HASH(u o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- 注意：EXPLAIN PLAN 不实际执行查询
-- 注意：DBMS_XPLAN.DISPLAY_CURSOR 显示实际执行计划（需要先执行）
-- 注意：GATHER_PLAN_STATISTICS 提示启用运行时统计收集
-- 注意：10046 跟踪提供最详细的诊断信息
-- 注意：SQL Monitor 对长时间运行的查询自动启动
-- 注意：执行计划可能因统计信息变化而改变
