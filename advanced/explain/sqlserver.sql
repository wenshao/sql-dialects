-- SQL Server: 执行计划与查询分析
--
-- 参考资料:
--   [1] Microsoft Docs - Execution Plans
--       https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans
--   [2] Microsoft Docs - SET STATISTICS
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/set-statistics-io-transact-sql
--   [3] Microsoft Docs - Showplan
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/set-showplan-all-transact-sql

-- ============================================================
-- 估算执行计划（不执行查询）
-- ============================================================

-- 文本格式
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM users WHERE username = 'alice';
GO
SET SHOWPLAN_TEXT OFF;
GO

-- 详细文本格式（含估算行数、成本等）
SET SHOWPLAN_ALL ON;
GO
SELECT * FROM users WHERE age > 25;
GO
SET SHOWPLAN_ALL OFF;
GO

-- XML 格式（最详细，SSMS 可图形化显示）
SET SHOWPLAN_XML ON;
GO
SELECT * FROM users WHERE age > 25;
GO
SET SHOWPLAN_XML OFF;
GO

-- ============================================================
-- 实际执行计划（执行查询并收集统计）
-- ============================================================

-- 文本格式
SET STATISTICS PROFILE ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS PROFILE OFF;

-- XML 格式
SET STATISTICS XML ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS XML OFF;

-- ============================================================
-- SET STATISTICS（运行时统计）
-- ============================================================

-- I/O 统计
SET STATISTICS IO ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS IO OFF;
-- 输出：Table 'users'. Scan count 1, logical reads 10, physical reads 2...

-- 时间统计
SET STATISTICS TIME ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS TIME OFF;
-- 输出：SQL Server parse and compile time... SQL Server Execution Times...

-- 同时启用
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- ============================================================
-- SSMS 图形化执行计划
-- ============================================================

-- 快捷键：
-- Ctrl+L    估算执行计划（不执行）
-- Ctrl+M    启用实际执行计划（执行时自动显示）

-- 也可以在查询前添加：
-- 在 SSMS 中点击 "Include Actual Execution Plan" 按钮

-- ============================================================
-- 实时查询统计（2016+）
-- ============================================================

-- 查看正在执行的查询的实时计划
SELECT * FROM sys.dm_exec_query_statistics_xml(session_id);

-- 查看活动查询及其计划
SELECT r.session_id, r.status, r.command,
       t.text AS sql_text,
       p.query_plan
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) p
WHERE r.session_id > 50;

-- ============================================================
-- 查询存储（Query Store，2016+）
-- ============================================================

-- 启用查询存储
ALTER DATABASE mydb SET QUERY_STORE = ON;
ALTER DATABASE mydb SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO
);

-- 查看性能最差的查询
SELECT TOP 10
    qt.query_sql_text,
    rs.avg_duration / 1000 AS avg_ms,
    rs.avg_logical_io_reads,
    rs.count_executions,
    qp.query_plan
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan qp ON q.query_id = qp.query_id
JOIN sys.query_store_runtime_stats rs ON qp.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;

-- 强制使用特定执行计划
EXEC sp_query_store_force_plan @query_id = 1, @plan_id = 1;

-- ============================================================
-- 执行计划关键操作符
-- ============================================================

-- Table Scan           全表扫描（堆表）
-- Clustered Index Scan 聚集索引扫描
-- Clustered Index Seek 聚集索引查找
-- Index Scan           非聚集索引扫描
-- Index Seek           非聚集索引查找
-- Key Lookup           键查找（回表）
-- RID Lookup           RID 查找（堆表回表）
-- Nested Loops         嵌套循环
-- Hash Match           哈希匹配（连接/聚合）
-- Merge Join           合并连接
-- Sort                 排序
-- Stream Aggregate     流聚合
-- Hash Aggregate       哈希聚合
-- Parallelism          并行操作

-- ============================================================
-- Hint 控制执行计划
-- ============================================================

-- 强制索引
SELECT * FROM users WITH (INDEX(IX_users_age))
WHERE age > 25;

-- 强制连接方式
SELECT u.username, o.amount
FROM users u
INNER LOOP JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u
INNER HASH JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u
INNER MERGE JOIN orders o ON u.id = o.user_id;

-- 查询选项
SELECT * FROM users WHERE age > 25
OPTION (MAXDOP 4);                    -- 最大并行度

SELECT * FROM users WHERE age > 25
OPTION (RECOMPILE);                   -- 强制重新编译

SELECT * FROM users WHERE age > 25
OPTION (OPTIMIZE FOR (@age = 30));    -- 针对特定值优化

-- ============================================================
-- DMV 查询性能视图
-- ============================================================

-- 缓存的执行计划
SELECT TOP 10
    cp.objtype, cp.usecounts, cp.size_in_bytes,
    t.text AS sql_text, qp.query_plan
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) t
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
ORDER BY cp.usecounts DESC;

-- 最消耗资源的查询
SELECT TOP 10
    qs.total_logical_reads, qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS avg_reads,
    t.text AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
ORDER BY qs.total_logical_reads DESC;

-- 注意：SET SHOWPLAN 显示估算计划（不执行），SET STATISTICS PROFILE 显示实际计划
-- 注意：XML 格式计划可在 SSMS 中图形化查看
-- 注意：Query Store（2016+）可以跟踪计划变化并强制使用特定计划
-- 注意：SET STATISTICS IO 是定位性能问题最常用的工具
-- 注意：logical reads 是衡量查询效率的核心指标
