-- Materialize: 执行计划与查询分析
--
-- 参考资料:
--   [1] Materialize Documentation - EXPLAIN
--       https://materialize.com/docs/sql/explain-plan/
--   [2] Materialize Documentation - Performance
--       https://materialize.com/docs/ops/troubleshooting/

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 选项
-- ============================================================

-- 原始计划
EXPLAIN RAW PLAN FOR SELECT * FROM users WHERE age > 25;

-- 装饰计划（含类型信息）
EXPLAIN DECORRELATED PLAN FOR SELECT * FROM users WHERE age > 25;

-- 优化计划
EXPLAIN OPTIMIZED PLAN FOR SELECT * FROM users WHERE age > 25;

-- 物理计划
EXPLAIN PHYSICAL PLAN FOR SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 用于物化视图
-- ============================================================

-- 查看物化视图的数据流计划
EXPLAIN OPTIMIZED PLAN FOR
CREATE MATERIALIZED VIEW active_user_orders AS
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- Get              获取数据源
-- Filter           过滤
-- Map              映射/投影
-- Join             连接
-- Reduce           聚合
-- TopK             Top K
-- Arrange          排列（创建索引）
-- Threshold        阈值（差分变更）
-- Union            联合
-- Negate           取反（差分运算）

-- ============================================================
-- 差分数据流（Differential Dataflow）
-- ============================================================

-- Materialize 基于差分数据流：
-- - 增量计算（只处理变化的部分）
-- - Arrangement（维护索引化的状态）
-- - 多时间版本（Frontier）

-- ============================================================
-- 系统目录查询
-- ============================================================

-- 查看物化视图的内存使用
SELECT name, memory_bytes, rehydration_latency
FROM mz_internal.mz_materialization_statistics;

-- 查看数据流的进度
SELECT * FROM mz_internal.mz_compute_frontiers;

-- 查看连接器状态
SELECT * FROM mz_internal.mz_source_statistics;

-- ============================================================
-- 性能监控
-- ============================================================

-- 查看活跃的 peek（查询）
SELECT * FROM mz_internal.mz_active_peeks;

-- 查看 Arrangement 大小
SELECT name, records, batches, size
FROM mz_internal.mz_arrangement_sizes;

-- 注意：Materialize 使用差分数据流，执行计划与传统数据库不同
-- 注意：EXPLAIN 支持多个层次：RAW, DECORRELATED, OPTIMIZED, PHYSICAL
-- 注意：Arrangement 是 Materialize 的核心概念（类似索引化状态）
-- 注意：增量计算意味着只处理数据变化，而非重新计算
-- 注意：mz_internal schema 提供系统运行时信息
