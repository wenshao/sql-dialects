-- Greenplum: 执行计划与查询分析
--
-- 参考资料:
--   [1] Greenplum Documentation - EXPLAIN
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-EXPLAIN.html
--   [2] Greenplum Documentation - Query Profiling
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-query-topics-query-profiling.html

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

-- 与 PostgreSQL 语法兼容
EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN ANALYZE
-- ============================================================

EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- 输出包含 Greenplum 特有的分布式执行信息：
-- Gather Motion（汇集数据到主节点）
-- Redistribute Motion（按连接键重分布）
-- Broadcast Motion（广播到所有段）

-- ============================================================
-- 输出格式
-- ============================================================

EXPLAIN (FORMAT TEXT) SELECT * FROM users;
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT YAML) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT XML) SELECT * FROM users WHERE age > 25;

-- 完整选项
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT u.*, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;

-- ============================================================
-- 关键操作符（Greenplum 特有）
-- ============================================================

-- Gather Motion 1:N       将段数据汇集到主节点
-- Redistribute Motion N:N 按哈希键重分布到各段
-- Broadcast Motion N:N    广播到所有段
-- Seq Scan                顺序扫描
-- Index Scan              索引扫描
-- Hash Join               哈希连接
-- Nested Loop             嵌套循环
-- Sort                    排序
-- HashAggregate           哈希聚合
-- GroupAggregate           分组聚合

-- Motion 是 Greenplum MPP 的关键操作
-- Motion 过多或数据量大时需要优化分布键

-- ============================================================
-- 分布键分析
-- ============================================================

-- 查看表的分布策略
SELECT localoid::regclass, policytype, distkey, distclass
FROM gp_distribution_policy
WHERE localoid = 'users'::regclass;

-- 检查数据倾斜
SELECT gp_segment_id, COUNT(*) AS row_count
FROM users
GROUP BY gp_segment_id
ORDER BY row_count DESC;

-- ============================================================
-- 资源队列监控
-- ============================================================

-- 查看活动查询
SELECT * FROM pg_stat_activity WHERE state = 'active';

-- 查看资源队列等待
SELECT * FROM gp_toolkit.gp_resqueue_status;

-- ============================================================
-- gp_toolkit 诊断视图
-- ============================================================

-- 表的大小和倾斜
SELECT * FROM gp_toolkit.gp_skew_coefficients
WHERE skcrelname = 'users';

-- 缺失统计信息的表
SELECT * FROM gp_toolkit.gp_stats_missing;

-- ============================================================
-- 统计信息
-- ============================================================

ANALYZE users;
ANALYZE users (username, age);

-- 注意：Greenplum 基于 PostgreSQL，EXPLAIN 语法类似
-- 注意：Motion 操作符是 Greenplum MPP 的核心，表示节点间数据移动
-- 注意：Broadcast Motion 适合小表，Redistribute Motion 适合大表连接
-- 注意：数据倾斜会严重影响并行执行效率
-- 注意：gp_toolkit 提供丰富的诊断视图
