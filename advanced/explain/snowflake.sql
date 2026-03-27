-- Snowflake: 执行计划与查询分析
--
-- 参考资料:
--   [1] Snowflake Documentation - Query Profile
--       https://docs.snowflake.com/en/user-guide/ui-query-profile
--   [2] Snowflake Documentation - EXPLAIN
--       https://docs.snowflake.com/en/sql-reference/sql/explain
--   [3] Snowflake Documentation - Query History
--       https://docs.snowflake.com/en/sql-reference/account-usage/query_history

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

-- 文本格式（默认）
EXPLAIN SELECT * FROM users WHERE username = 'alice';

-- 表格格式
EXPLAIN USING TABULAR SELECT * FROM users WHERE age > 25;

-- JSON 格式
EXPLAIN USING JSON SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 输出字段
-- ============================================================

-- GlobalStats:    全局统计（分区总数、扫描分区数）
-- Operations:     操作列表
--   - operation:  操作类型
--   - objects:    涉及的对象
--   - expressions: 表达式
--   - partitionsTotal: 总分区数
--   - partitionsAssigned: 扫描的分区数

-- ============================================================
-- Query Profile（Web UI，推荐）
-- ============================================================

-- 在 Snowsight Web UI 中：
-- 1. 执行查询
-- 2. 点击 Query ID 链接
-- 3. 查看 "Query Profile" 选项卡

-- Query Profile 提供：
-- - 操作符树（图形化 DAG）
-- - 每个操作符的统计信息
-- - 数据溢出（spilling）信息
-- - 分区裁剪效果
-- - 并行度
-- - 最慢的操作符

-- ============================================================
-- 查询历史
-- ============================================================

-- 通过 QUERY_HISTORY 函数
SELECT *
FROM TABLE(information_schema.query_history(
    dateadd('hours', -1, current_timestamp()),
    current_timestamp(),
    100
))
ORDER BY start_time DESC;

-- 通过 Account Usage 视图（延迟最多 45 分钟）
SELECT
    query_id,
    query_text,
    execution_status,
    total_elapsed_time / 1000 AS elapsed_sec,
    bytes_scanned / 1048576 AS mb_scanned,
    rows_produced,
    partitions_scanned,
    partitions_total,
    compilation_time,
    execution_time
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC
LIMIT 20;

-- ============================================================
-- 性能分析关键指标
-- ============================================================

-- 分区裁剪（Partition Pruning）
-- 最重要的性能指标之一
SELECT
    query_id,
    partitions_scanned,
    partitions_total,
    ROUND(partitions_scanned / NULLIF(partitions_total, 0) * 100, 2) AS pct_scanned
FROM snowflake.account_usage.query_history
WHERE start_time > DATEADD('day', -1, CURRENT_TIMESTAMP())
  AND partitions_total > 0
ORDER BY partitions_scanned DESC
LIMIT 10;

-- 数据溢出（Spilling）
SELECT
    query_id,
    query_text,
    bytes_spilled_to_local_storage,
    bytes_spilled_to_remote_storage
FROM snowflake.account_usage.query_history
WHERE bytes_spilled_to_local_storage > 0
   OR bytes_spilled_to_remote_storage > 0
ORDER BY start_time DESC
LIMIT 10;

-- ============================================================
-- SYSTEM$EXPLAIN_PLAN_JSON（编程方式）
-- ============================================================

-- 返回 JSON 格式的执行计划
SELECT SYSTEM$EXPLAIN_PLAN_JSON(
    'SELECT * FROM users WHERE age > 25'
);

-- ============================================================
-- 查询标记（Query Tag）
-- ============================================================

-- 设置查询标记方便后续分析
ALTER SESSION SET QUERY_TAG = 'performance_test';
SELECT * FROM users WHERE age > 25;
ALTER SESSION UNSET QUERY_TAG;

-- 按标记查询历史
SELECT * FROM snowflake.account_usage.query_history
WHERE query_tag = 'performance_test'
ORDER BY start_time DESC;

-- ============================================================
-- 资源监控
-- ============================================================

-- 仓库负载历史
SELECT *
FROM TABLE(information_schema.warehouse_load_history(
    date_range_start => dateadd('hour', -4, current_timestamp())
));

-- 仓库计量历史
SELECT *
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY credits_used DESC;

-- ============================================================
-- Query Profile 关键操作符
-- ============================================================

-- TableScan            表扫描
-- Filter               过滤
-- JoinFilter           连接过滤
-- Projection           投影
-- Aggregate            聚合
-- Sort                 排序
-- SortWithLimit        带 LIMIT 的排序
-- HashJoin             哈希连接
-- WindowFunction       窗口函数
-- UnionAll             UNION ALL
-- WithClause           CTE
-- ExternalScan         外部表扫描

-- 注意：Snowflake 的 EXPLAIN 不实际执行查询
-- 注意：Query Profile（Web UI）提供最详细的图形化执行计划
-- 注意：分区裁剪（Partition Pruning）是 Snowflake 最重要的优化指标
-- 注意：数据溢出（Spilling）到磁盘或远程存储表示需要更大的仓库
-- 注意：Snowflake 自动管理集群，无需手动调整执行计划
-- 注意：Query Tag 方便对查询进行分类和追踪
