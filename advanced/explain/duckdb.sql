-- DuckDB: 执行计划与查询分析
--
-- 参考资料:
--   [1] DuckDB Documentation - EXPLAIN
--       https://duckdb.org/docs/guides/meta/explain
--   [2] DuckDB Documentation - EXPLAIN ANALYZE
--       https://duckdb.org/docs/guides/meta/explain_analyze
--   [3] DuckDB Documentation - Profiling
--       https://duckdb.org/docs/dev/profiling

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

-- 显示查询的逻辑计划和物理计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- 输出包含两部分：
-- 1. 逻辑计划（Logical Plan）
-- 2. 物理计划（Physical Plan）

-- ============================================================
-- EXPLAIN ANALYZE（实际执行）
-- ============================================================

-- 执行查询并收集运行时统计
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- 输出包含：
-- - 每个操作符的实际执行时间
-- - 实际处理的行数
-- - 内存使用情况

EXPLAIN ANALYZE
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC;

-- ============================================================
-- Profiling（详细性能分析）
-- ============================================================

-- 启用性能分析
PRAGMA enable_profiling;

-- 设置输出格式
PRAGMA enable_profiling = 'json';       -- JSON 格式
PRAGMA enable_profiling = 'query_tree'; -- 树形格式（默认）

-- 输出到文件
PRAGMA profiling_output = '/tmp/profile.json';

-- 执行查询（自动输出性能信息）
SELECT * FROM users WHERE age > 25;

-- 关闭性能分析
PRAGMA disable_profiling;

-- ============================================================
-- 详细 Profiling 设置
-- ============================================================

-- 启用详细的操作符 profiling
PRAGMA enable_progress_bar;
PRAGMA enable_profiling = 'json';
PRAGMA profiling_mode = 'detailed';  -- 详细模式

-- ============================================================
-- 物理计划操作符
-- ============================================================

-- SEQ_SCAN             顺序扫描
-- INDEX_SCAN           索引扫描
-- FILTER               过滤
-- PROJECTION           投影
-- HASH_JOIN            哈希连接
-- PIECEWISE_MERGE_JOIN 分段合并连接
-- NESTED_LOOP_JOIN     嵌套循环连接
-- HASH_GROUP_BY        哈希分组
-- PERFECT_HASH_GROUP_BY 完美哈希分组
-- ORDER_BY             排序
-- LIMIT                限制
-- UNGROUPED_AGGREGATE  无分组聚合
-- WINDOW               窗口函数
-- TOP_N                Top N 排序

-- ============================================================
-- 查询优化器设置
-- ============================================================

-- 禁用特定优化（用于调试）
PRAGMA disabled_optimizers = 'filter_pushdown';

-- 查看所有优化器
SELECT * FROM duckdb_optimizers();

-- 设置线程数（影响并行度）
SET threads = 4;

-- 设置内存限制
SET memory_limit = '2GB';

-- ============================================================
-- 表信息和统计
-- ============================================================

-- 查看表的存储信息
SELECT * FROM pragma_storage_info('users');

-- 查看表的数据库大小
SELECT * FROM pragma_database_size();

-- 表的元数据
DESCRIBE users;
SELECT * FROM information_schema.columns WHERE table_name = 'users';

-- ============================================================
-- 性能基准
-- ============================================================

-- DuckDB 内置的 benchmark
-- .timer on    -- CLI 中启用计时

PRAGMA enable_profiling;
SELECT user_id, SUM(amount) AS total
FROM orders
GROUP BY user_id
HAVING SUM(amount) > 1000
ORDER BY total DESC
LIMIT 10;
PRAGMA disable_profiling;

-- 注意：EXPLAIN 显示逻辑计划和物理计划
-- 注意：EXPLAIN ANALYZE 实际执行并收集运行时统计
-- 注意：Profiling 可以输出 JSON 格式方便可视化分析
-- 注意：DuckDB 使用向量化执行引擎，Pipeline 并行处理
-- 注意：DuckDB 对列式存储和内存中分析查询高度优化
-- 注意：PRAGMA disabled_optimizers 可以禁用特定优化器进行调试
