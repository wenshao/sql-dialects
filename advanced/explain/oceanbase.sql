-- OceanBase: 执行计划与查询分析
--
-- 参考资料:
--   [1] OceanBase Documentation - EXPLAIN
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Documentation - SQL Tuning
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE username = 'alice';

-- ============================================================
-- EXPLAIN 格式
-- ============================================================

-- 基本格式
EXPLAIN BASIC SELECT * FROM users WHERE age > 25;

-- 大纲格式
EXPLAIN OUTLINE SELECT * FROM users WHERE age > 25;

-- 扩展格式（含成本信息）
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;

-- 全部信息
EXPLAIN EXTENDED_NOADDR SELECT * FROM users WHERE age > 25;

-- JSON 格式
EXPLAIN FORMAT = JSON SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- TABLE SCAN             全表扫描
-- TABLE GET              主键精确查找
-- INDEX SCAN             索引扫描
-- INDEX GET              索引精确查找
-- NESTED LOOP JOIN       嵌套循环连接
-- HASH JOIN              哈希连接
-- MERGE JOIN             合并连接
-- SORT                   排序
-- HASH GROUP BY          哈希分组
-- MERGE GROUP BY         合并分组
-- EXCHANGE               分布式数据交换
-- SUBPLAN FILTER         子查询过滤

-- 分布式操作：
-- EXCHANGE OUT           发送数据
-- EXCHANGE IN            接收数据
-- PX PARTITION ITERATOR  分区迭代器
-- PX COORDINATOR         并行协调器

-- ============================================================
-- 实际执行计划（4.0+）
-- ============================================================

-- OceanBase 通过 SQL Audit 获取实际执行统计
SELECT query_sql, elapsed_time, execute_time, queue_time,
       return_rows, affected_rows, plan_type
FROM oceanbase.GV$OB_SQL_AUDIT
WHERE query_sql LIKE '%users%'
ORDER BY request_time DESC
LIMIT 10;

-- ============================================================
-- Plan Cache（计划缓存）
-- ============================================================

-- 查看缓存的执行计划
SELECT sql_id, plan_id, type, plan_size, executions,
       avg_exe_usec, hit_count
FROM oceanbase.GV$OB_PLAN_CACHE_PLAN_STAT
ORDER BY avg_exe_usec DESC
LIMIT 10;

-- 查看特定计划的详细信息
SELECT operator, name, rows, cost
FROM oceanbase.GV$OB_PLAN_CACHE_PLAN_EXPLAIN
WHERE plan_id = 12345;

-- ============================================================
-- SQL Trace
-- ============================================================

-- 启用 SQL Trace
SET ob_enable_trace_log = 1;

SELECT * FROM users WHERE age > 25;

-- 查看 Trace
SHOW TRACE;

-- ============================================================
-- Outline（执行计划绑定）
-- ============================================================

-- 创建 Outline 绑定特定执行计划
CREATE OUTLINE outline_name ON
SELECT * FROM users WHERE age > 25
USING /*+ INDEX(users idx_users_age) */
SELECT * FROM users WHERE age > 25;

-- 查看 Outline
SELECT * FROM oceanbase.DBA_OB_OUTLINES;

-- ============================================================
-- 统计信息
-- ============================================================

-- OceanBase MySQL 模式
ANALYZE TABLE users;

-- OceanBase Oracle 模式
-- EXEC DBMS_STATS.GATHER_TABLE_STATS('SCHEMA', 'USERS');

-- 注意：OceanBase 兼容 MySQL 和 Oracle 两种模式
-- 注意：EXPLAIN 语法在 MySQL 模式下类似 MySQL
-- 注意：GV$OB_SQL_AUDIT 是分析查询性能的主要工具
-- 注意：Plan Cache 缓存执行计划避免重复编译
-- 注意：Outline 可以绑定特定执行计划（类似 Oracle 的 SQL Plan Baseline）
-- 注意：分布式查询计划包含 EXCHANGE 操作符
