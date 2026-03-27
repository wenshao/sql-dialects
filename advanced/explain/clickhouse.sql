-- ClickHouse: 执行计划与查询分析
--
-- 参考资料:
--   [1] ClickHouse Documentation - EXPLAIN
--       https://clickhouse.com/docs/en/sql-reference/statements/explain
--   [2] ClickHouse Documentation - Query Profiling
--       https://clickhouse.com/docs/en/operations/optimizing-performance/sampling-query-profiler

-- ============================================================
-- EXPLAIN 基本用法（20.6+）
-- ============================================================

-- 查看查询计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 类型
-- ============================================================

-- EXPLAIN PLAN（默认）
EXPLAIN PLAN SELECT * FROM users WHERE age > 25;

-- 带 header 和 actions
EXPLAIN header = 1, actions = 1
SELECT * FROM users WHERE age > 25;

-- EXPLAIN PIPELINE（数据处理管道）
EXPLAIN PIPELINE SELECT * FROM users WHERE age > 25;

-- 带线程数
EXPLAIN PIPELINE header = 1, graph = 1
SELECT * FROM users WHERE age > 25;

-- EXPLAIN SYNTAX（优化后的 SQL）
EXPLAIN SYNTAX SELECT * FROM users WHERE 1 = 1 AND age > 25;

-- EXPLAIN AST（抽象语法树）
EXPLAIN AST SELECT * FROM users WHERE age > 25;

-- EXPLAIN ESTIMATE（估算读取的行/字节数，20.12+）
EXPLAIN ESTIMATE SELECT * FROM users WHERE age > 25;

-- EXPLAIN TABLE OVERRIDE（22.8+）
EXPLAIN TABLE OVERRIDE mysql('host:port', 'db', 'table', 'user', 'password');

-- ============================================================
-- EXPLAIN PLAN 详细选项
-- ============================================================

EXPLAIN
    header = 1,           -- 显示列头
    description = 1,      -- 显示描述
    actions = 1,          -- 显示操作
    json = 1              -- JSON 格式输出
SELECT u.username, COUNT(*) AS cnt
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY cnt DESC;

-- ============================================================
-- EXPLAIN PIPELINE 详解
-- ============================================================

-- 查看执行管道（处理器和端口）
EXPLAIN PIPELINE
SELECT user_id, SUM(amount)
FROM orders
GROUP BY user_id;

-- 图形化格式（可用 graphviz 渲染）
EXPLAIN PIPELINE graph = 1
SELECT user_id, SUM(amount)
FROM orders
GROUP BY user_id;

-- 输出示例：
-- (Expression)
-- ExpressionTransform × 8
--   (Aggregating)
--   Resize 8 → 8
--     AggregatingTransform × 8
--       (Expression)
--       ExpressionTransform × 8
--         (ReadFromMergeTree)
--         MergeTreeThread × 8

-- ============================================================
-- 查询日志与性能分析
-- ============================================================

-- 启用查询日志（默认启用）
-- 查看最近的查询
SELECT
    query_id,
    query,
    type,
    event_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    result_rows,
    memory_usage
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;

-- 查看特定查询的详细信息
SELECT
    query_duration_ms,
    read_rows,
    read_bytes / 1048576 AS read_mb,
    written_rows,
    result_rows,
    memory_usage / 1048576 AS memory_mb,
    ProfileEvents
FROM system.query_log
WHERE query_id = 'your-query-id'
AND type = 'QueryFinish';

-- ============================================================
-- 查询性能事件（ProfileEvents）
-- ============================================================

-- 查看特定查询的性能计数器
SELECT
    query_id,
    ProfileEvents['SelectedRows'] AS selected_rows,
    ProfileEvents['SelectedBytes'] AS selected_bytes,
    ProfileEvents['FileOpen'] AS file_opens,
    ProfileEvents['ReadBufferFromFileDescriptorReadBytes'] AS disk_read_bytes,
    ProfileEvents['OSCPUVirtualTimeMicroseconds'] AS cpu_us
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 5;

-- ============================================================
-- 查询线程日志
-- ============================================================

SELECT
    thread_name,
    read_rows,
    read_bytes,
    peak_memory_usage
FROM system.query_thread_log
WHERE query_id = 'your-query-id';

-- ============================================================
-- 实时查看正在执行的查询
-- ============================================================

SELECT
    query_id,
    query,
    elapsed,
    read_rows,
    total_rows_approx,
    memory_usage,
    is_cancelled
FROM system.processes
WHERE is_initial_query = 1;

-- 终止查询
-- KILL QUERY WHERE query_id = 'query-id';

-- ============================================================
-- clickhouse-benchmark 工具
-- ============================================================

-- 命令行基准测试（不是 SQL）：
-- clickhouse-benchmark --query "SELECT * FROM users WHERE age > 25" -i 100

-- ============================================================
-- 关键优化指标
-- ============================================================

-- 1. 主键过滤：ClickHouse MergeTree 通过主键跳过 granule
-- 2. 分区裁剪：WHERE 条件匹配分区键
-- 3. 预聚合：使用 AggregatingMergeTree 等
-- 4. 向量化执行：Pipeline 中的并行处理器数量

-- 检查数据跳过效果
EXPLAIN ESTIMATE
SELECT * FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2024-02-01';

-- 注意：EXPLAIN 从 20.6 版本开始支持
-- 注意：EXPLAIN PIPELINE 展示了 ClickHouse 向量化执行引擎的处理器拓扑
-- 注意：EXPLAIN SYNTAX 可以查看优化器重写后的查询
-- 注意：system.query_log 是分析历史查询性能的主要工具
-- 注意：ClickHouse 没有传统的基于成本的执行计划，因为它使用向量化执行
