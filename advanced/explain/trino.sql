-- Trino (formerly PrestoSQL): 执行计划与查询分析
--
-- 参考资料:
--   [1] Trino Documentation - EXPLAIN
--       https://trino.io/docs/current/sql/explain.html
--   [2] Trino Documentation - EXPLAIN ANALYZE
--       https://trino.io/docs/current/sql/explain-analyze.html
--   [3] Trino Documentation - Performance Tuning
--       https://trino.io/docs/current/admin/tuning.html

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

-- 显示逻辑执行计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 格式
-- ============================================================

-- 文本格式（默认）
EXPLAIN (FORMAT TEXT) SELECT * FROM users WHERE age > 25;

-- 图形化格式（DOT / graphviz）
EXPLAIN (FORMAT GRAPHVIZ) SELECT * FROM users WHERE age > 25;

-- JSON 格式
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 计划类型
-- ============================================================

-- 逻辑计划（默认）
EXPLAIN (TYPE LOGICAL) SELECT * FROM users WHERE age > 25;

-- 分布式计划
EXPLAIN (TYPE DISTRIBUTED) SELECT * FROM users WHERE age > 25;

-- IO 计划（显示 IO 估算）
EXPLAIN (TYPE IO) SELECT * FROM users WHERE age > 25;

-- VALIDATE（只验证查询语法）
EXPLAIN (TYPE VALIDATE) SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN ANALYZE（实际执行）
-- ============================================================

EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- 输出包含：
-- CPU time / Wall time
-- Input rows / Output rows
-- Physical input / output bytes
-- 每个阶段的详细统计

EXPLAIN ANALYZE
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC;

-- ============================================================
-- EXPLAIN ANALYZE 详细信息
-- ============================================================

-- 输出示例中的关键指标：
-- Fragment 0 [SINGLE]
--   CPU: 10.00ms, Input: 100 rows (5.2kB), Output: 100 rows (5.2kB)
-- Fragment 1 [HASH]
--   CPU: 50.00ms, Input: 10000 rows (500kB)
--   ScanFilter[table = hive.default.users, ...]
--     Input: 10000 rows, Filtered: 7200 rows

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- ScanFilter           扫描 + 过滤下推
-- Project              投影
-- InnerJoin / LeftJoin 连接
-- HashBuilderOperator  哈希连接构建端
-- LookupJoinOperator   查找连接
-- Aggregate            聚合
-- TopN                 Top N 排序
-- Sort                 排序
-- Exchange             数据交换（节点间传输）
-- Output               输出

-- 分布式计划标记：
-- SINGLE       单节点执行
-- HASH         按哈希分布
-- ROUND_ROBIN  轮询分布
-- BROADCAST    广播
-- SOURCE       数据源节点

-- ============================================================
-- 查询监控（Web UI）
-- ============================================================

-- Trino Web UI（默认端口 8080）提供：
-- - 活跃查询列表
-- - 查询详情（执行计划、各阶段统计）
-- - 资源使用（CPU、内存）
-- - Worker 节点状态

-- ============================================================
-- 系统表查询
-- ============================================================

-- 查看运行中的查询
SELECT query_id, state, query, queued_time_ms, analysis_time_ms,
       planning_time_ms, total_cpu_time, peak_user_memory_bytes
FROM system.runtime.queries
WHERE state = 'RUNNING';

-- 查看已完成的查询
SELECT query_id, query, execution_time_ms,
       total_bytes, total_rows
FROM system.runtime.queries
WHERE state = 'FINISHED'
ORDER BY end DESC
LIMIT 10;

-- ============================================================
-- Session 属性调优
-- ============================================================

-- 连接类型
SET SESSION join_distribution_type = 'AUTOMATIC';  -- 或 BROADCAST, PARTITIONED
SET SESSION join_reordering_strategy = 'AUTOMATIC';

-- 内存限制
SET SESSION query_max_memory = '2GB';
SET SESSION query_max_memory_per_node = '512MB';

-- 注意：EXPLAIN 显示逻辑计划，EXPLAIN (TYPE DISTRIBUTED) 显示分布式计划
-- 注意：EXPLAIN ANALYZE 实际执行查询并收集运行时统计
-- 注意：FORMAT GRAPHVIZ 可以生成 DOT 格式用于可视化
-- 注意：Exchange 操作符表示节点间数据传输，是分布式查询的开销所在
-- 注意：Web UI 提供实时的查询监控和性能分析
-- 注意：EXPLAIN (TYPE IO) 可以查看数据源 IO 估算
