-- Vertica: 执行计划与查询分析
--
-- 参考资料:
--   [1] Vertica Documentation - EXPLAIN
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/EXPLAIN.htm
--   [2] Vertica Documentation - Query Performance
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/AnalyzingData/Optimizations/QueryOptimization.htm

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- 输出示例：
-- Access Path:
-- +-STORAGE ACCESS for users [Cost: 100, Rows: 280]
-- |  Projection: public.users_b0
-- |  Filter: (users.age > 25)

-- ============================================================
-- EXPLAIN VERBOSE
-- ============================================================

-- 详细输出
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 用于连接
-- ============================================================

EXPLAIN
SELECT u.username, SUM(o.amount) AS total
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY total DESC;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- STORAGE ACCESS      存储访问（从 Projection 读取）
-- FILTER              过滤
-- JOIN                连接（Hash Join, Merge Join）
-- GROUP BY HASH       哈希分组
-- GROUP BY PIPE       管道分组
-- SORT                排序
-- LIMIT               限制
-- UNION               联合
-- ANALYTIC            分析函数
-- RESEGMENT           重新分段（节点间数据移动）
-- BROADCAST           广播（发送到所有节点）

-- ============================================================
-- PROFILE（实际执行统计）
-- ============================================================

-- 启用查询性能分析
-- 需要先执行 PROFILE 语句
PROFILE SELECT * FROM users WHERE age > 25;

-- 查看性能分析结果
SELECT * FROM query_profiles
ORDER BY query_start DESC LIMIT 5;

-- 详细的执行步骤
SELECT node_name, operator_name, counter_name, counter_value
FROM execution_engine_profiles
WHERE transaction_id = (SELECT transaction_id FROM query_profiles
                        ORDER BY query_start DESC LIMIT 1)
ORDER BY operator_id;

-- ============================================================
-- QUERY_REQUESTS 系统表
-- ============================================================

SELECT request_id, request, request_duration_ms,
       memory_acquired_mb, processed_row_count
FROM query_requests
WHERE is_executing = 'f'
ORDER BY start_timestamp DESC
LIMIT 10;

-- ============================================================
-- Projection 分析
-- ============================================================

-- 查看 Projection 使用情况
SELECT projection_name, anchor_table_name, is_super_projection,
       row_count, used_bytes
FROM projections
WHERE anchor_table_name = 'users';

-- Vertica 性能的关键在于 Projection 设计
-- 好的 Projection = 正确的排序列 + 分段策略

-- ============================================================
-- 资源池监控
-- ============================================================

SELECT pool_name, running_query_count, memory_inuse_kb,
       general_memory_borrowed_kb, planned_concurrency
FROM resource_pool_status;

-- ============================================================
-- 统计信息
-- ============================================================

SELECT ANALYZE_STATISTICS('users');

-- 查看表统计
SELECT * FROM column_statistics WHERE table_name = 'users';

-- 注意：Vertica 的执行计划基于 Projection（预排序的列存储投影）
-- 注意：PROFILE 语句实际执行查询并收集详细性能数据
-- 注意：RESEGMENT 操作表示节点间数据重新分布
-- 注意：Projection 设计（排序列、分段策略）是性能优化的核心
-- 注意：Vertica 的列存储和压缩使 STORAGE ACCESS 效率很高
