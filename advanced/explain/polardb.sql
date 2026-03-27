-- PolarDB: 执行计划与查询分析
--
-- 参考资料:
--   [1] PolarDB MySQL Documentation
--       https://help.aliyun.com/document_detail/316280.html
--   [2] PolarDB PostgreSQL Documentation
--       https://help.aliyun.com/document_detail/172538.html

-- ============================================================
-- PolarDB MySQL 兼容版
-- ============================================================

-- EXPLAIN 基本用法（与 MySQL 兼容）
EXPLAIN SELECT * FROM users WHERE username = 'alice';

-- 格式选项
EXPLAIN FORMAT=TRADITIONAL SELECT * FROM users WHERE age > 25;
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE age > 25;

-- EXPLAIN ANALYZE（实际执行）
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- ============================================================
-- PolarDB 特有功能：并行查询
-- ============================================================

-- 查看并行查询计划
EXPLAIN SELECT /*+ PARALLEL(4) */ * FROM users WHERE age > 25;

-- 并行查询特有操作：
-- ParallelScan      并行扫描
-- Gather            汇集并行结果

-- 查看并行查询是否生效
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE age > 25;
-- 输出中包含 "parallel scan" 表示并行查询启用

-- ============================================================
-- PolarDB PostgreSQL 兼容版
-- ============================================================

-- EXPLAIN（与 PostgreSQL 兼容）
EXPLAIN SELECT * FROM users WHERE age > 25;
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT * FROM users WHERE age > 25;

-- PolarDB PG 特有：ePQ（弹性并行查询）
-- 查看分布式执行计划
EXPLAIN (ANALYZE, VERBOSE)
SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 性能诊断
-- ============================================================

-- PolarDB MySQL: Performance Insight
-- 通过阿里云控制台查看：
-- - 活跃会话（AAS）
-- - Top SQL
-- - 等待事件分析

-- PolarDB MySQL: SQL 洞察
-- 记录所有 SQL 的详细执行信息

-- ============================================================
-- 统计信息
-- ============================================================

-- PolarDB MySQL
ANALYZE TABLE users;

-- PolarDB PostgreSQL
ANALYZE users;

-- 注意：PolarDB 分为 MySQL 兼容版和 PostgreSQL 兼容版
-- 注意：EXPLAIN 语法分别与 MySQL 和 PostgreSQL 兼容
-- 注意：并行查询是 PolarDB 的重要特性
-- 注意：阿里云控制台的 Performance Insight 提供图形化性能分析
-- 注意：SQL 洞察功能可以回溯历史 SQL 性能
