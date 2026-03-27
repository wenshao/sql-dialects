-- Spark SQL: 执行计划与查询分析
--
-- 参考资料:
--   [1] Spark Documentation - EXPLAIN
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-explain.html
--   [2] Spark Documentation - Performance Tuning
--       https://spark.apache.org/docs/latest/sql-performance-tuning.html

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 模式
-- ============================================================

-- 简要模式（只显示物理计划）
EXPLAIN FORMATTED SELECT * FROM users WHERE age > 25;

-- 扩展模式（逻辑计划 + 物理计划）
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;

-- 代码生成（Codegen）
EXPLAIN CODEGEN SELECT * FROM users WHERE age > 25;

-- 成本信息（3.0+）
EXPLAIN COST SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 执行计划层次
-- ============================================================

-- EXPLAIN EXTENDED 输出四个计划：
-- 1. Parsed Logical Plan    解析后的逻辑计划
-- 2. Analyzed Logical Plan  分析后的逻辑计划
-- 3. Optimized Logical Plan 优化后的逻辑计划
-- 4. Physical Plan          物理计划

EXPLAIN EXTENDED
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC;

-- ============================================================
-- 物理计划关键操作
-- ============================================================

-- FileScan              文件扫描（Parquet, ORC, CSV 等）
-- Filter                过滤
-- Project               投影
-- BroadcastHashJoin     广播哈希连接（小表广播）
-- SortMergeJoin         排序合并连接
-- ShuffledHashJoin      Shuffle 哈希连接
-- HashAggregate         哈希聚合
-- Sort                  排序
-- Exchange              数据交换（Shuffle）
-- WholeStageCodegen     全阶段代码生成（Tungsten）
-- InMemoryTableScan     内存表扫描（缓存的表）
-- SubqueryBroadcast     子查询广播

-- ============================================================
-- Spark Web UI
-- ============================================================

-- Spark Web UI（默认端口 4040）提供：
-- 1. SQL 页面：查看 SQL 查询的执行计划 DAG
-- 2. Stages 页面：各阶段的详细统计
-- 3. Storage 页面：缓存的 RDD/DataFrame
-- 4. Executors 页面：执行器资源使用

-- SQL 页面的执行计划图包含：
-- - 每个操作符的输入/输出行数
-- - Shuffle 读写量
-- - 溢出数据量

-- ============================================================
-- 自适应查询执行（AQE，3.0+）
-- ============================================================

-- 启用 AQE
SET spark.sql.adaptive.enabled = true;

-- AQE 功能：
-- 1. 动态合并 Shuffle 分区
SET spark.sql.adaptive.coalescePartitions.enabled = true;

-- 2. 动态切换连接策略
SET spark.sql.adaptive.localShuffleReader.enabled = true;

-- 3. 动态优化倾斜连接
SET spark.sql.adaptive.skewJoin.enabled = true;

-- ============================================================
-- 统计信息
-- ============================================================

-- 收集表统计信息
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, age;

-- 查看统计信息
DESCRIBE EXTENDED users;

-- ============================================================
-- 查询 Hint
-- ============================================================

-- 广播连接 Hint
SELECT /*+ BROADCAST(u) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- Shuffle 连接 Hint
SELECT /*+ SHUFFLE_HASH(o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- 合并连接 Hint
SELECT /*+ MERGE(u, o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- 数据倾斜 Hint（3.0+）
SELECT /*+ SKEW('orders') */ * FROM orders;

-- 注意：EXPLAIN EXTENDED 显示完整的逻辑计划和物理计划
-- 注意：EXPLAIN CODEGEN 显示生成的 Java 代码（Tungsten）
-- 注意：Spark Web UI 的 SQL 页面提供图形化执行计划
-- 注意：AQE（3.0+）可以在运行时动态优化执行计划
-- 注意：WholeStageCodegen 表示全阶段代码生成优化已启用
-- 注意：Exchange 操作符表示 Shuffle，是分布式计算的主要开销
