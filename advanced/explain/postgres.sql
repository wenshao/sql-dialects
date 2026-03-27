-- PostgreSQL: 执行计划与查询分析
--
-- 参考资料:
--   [1] PostgreSQL Documentation - EXPLAIN
--       https://www.postgresql.org/docs/current/sql-explain.html
--   [2] PostgreSQL Documentation - Using EXPLAIN
--       https://www.postgresql.org/docs/current/using-explain.html
--   [3] PostgreSQL Documentation - Performance Tips
--       https://www.postgresql.org/docs/current/performance-tips.html

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

-- 显示查询计划（不执行查询）
EXPLAIN SELECT * FROM users WHERE username = 'alice';

-- 输出示例：
-- Seq Scan on users  (cost=0.00..12.50 rows=1 width=100)
--   Filter: (username = 'alice')

-- cost 含义：
--   cost=启动成本..总成本（任意单位，通常基于磁盘页读取）
--   rows: 估算返回行数
--   width: 估算行宽度（字节）

-- ============================================================
-- EXPLAIN ANALYZE（实际执行）
-- ============================================================

-- 实际执行查询并收集运行时统计
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- 输出示例：
-- Seq Scan on users  (cost=0.00..12.50 rows=300 width=100) (actual time=0.015..0.120 rows=280 loops=1)
--   Filter: (age > 25)
--   Rows Removed by Filter: 720
-- Planning Time: 0.080 ms
-- Execution Time: 0.150 ms

-- 注意：EXPLAIN ANALYZE 会实际执行查询
-- 对于 DML，用事务回滚：
BEGIN;
EXPLAIN ANALYZE DELETE FROM users WHERE status = 0;
ROLLBACK;

-- ============================================================
-- 输出格式选项
-- ============================================================

-- 文本格式（默认）
EXPLAIN (FORMAT TEXT) SELECT * FROM users;

-- JSON 格式（结构化，方便程序解析）
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;

-- YAML 格式
EXPLAIN (FORMAT YAML) SELECT * FROM users WHERE age > 25;

-- XML 格式
EXPLAIN (FORMAT XML) SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 选项组合
-- ============================================================

-- 显示所有详细信息
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT u.*, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;

-- 各选项含义：
-- ANALYZE     实际执行并收集运行时信息
-- BUFFERS     显示缓冲区使用情况（共享/本地命中、读取、脏页、写入）
-- COSTS       显示成本估算（默认开启）
-- TIMING      显示实际时间（需要 ANALYZE）
-- VERBOSE     显示额外信息（输出列列表等）
-- SETTINGS    显示影响计划的非默认配置（12+）
-- WAL         显示 WAL 记录生成信息（13+，需要 ANALYZE）

-- 13+: 不计时的 ANALYZE（减少 gettimeofday 调用开销）
EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM users;

-- ============================================================
-- 常见执行计划节点
-- ============================================================

-- 扫描节点
EXPLAIN SELECT * FROM users;                              -- Seq Scan
EXPLAIN SELECT * FROM users WHERE id = 1;                 -- Index Scan
EXPLAIN SELECT id FROM users WHERE id > 100;              -- Index Only Scan
EXPLAIN SELECT * FROM users WHERE age IN (25, 30, 35);    -- Bitmap Heap Scan + Bitmap Index Scan

-- 连接节点
EXPLAIN SELECT * FROM users u JOIN orders o ON u.id = o.user_id;  -- Hash Join / Nested Loop / Merge Join

-- 聚合节点
EXPLAIN SELECT age, COUNT(*) FROM users GROUP BY age;     -- HashAggregate / GroupAggregate

-- 排序节点
EXPLAIN SELECT * FROM users ORDER BY age;                 -- Sort

-- ============================================================
-- BUFFERS 信息解读
-- ============================================================

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE age > 25;

-- 输出示例：
-- Seq Scan on users (...)
--   Buffers: shared hit=10 read=5
--
-- shared hit:   共享缓冲区命中（内存中）
-- shared read:  从磁盘读取
-- shared dirtied: 弄脏的页面
-- shared written: 写回的页面

-- ============================================================
-- 统计信息管理
-- ============================================================

-- 手动更新统计信息
ANALYZE users;
ANALYZE users (username, age);

-- 查看表的统计信息
SELECT relname, reltuples, relpages
FROM pg_class WHERE relname = 'users';

-- 查看列的统计信息
SELECT attname, n_distinct, most_common_vals, histogram_bounds
FROM pg_stats WHERE tablename = 'users';

-- 调整统计信息采样精度
ALTER TABLE users ALTER COLUMN username SET STATISTICS 1000;
ANALYZE users;

-- ============================================================
-- 查询计划控制
-- ============================================================

-- 禁用特定扫描/连接方式（用于测试）
SET enable_seqscan = off;
SET enable_indexscan = off;
SET enable_hashjoin = off;
SET enable_mergejoin = off;
SET enable_nestloop = off;

-- 恢复默认
RESET enable_seqscan;

-- 调整成本参数
SET random_page_cost = 1.1;     -- SSD 时可降低（默认 4.0）
SET seq_page_cost = 1.0;
SET effective_cache_size = '4GB';
SET work_mem = '256MB';

-- ============================================================
-- auto_explain 扩展
-- ============================================================

-- 自动记录慢查询的执行计划
-- postgresql.conf:
-- shared_preload_libraries = 'auto_explain'
-- auto_explain.log_min_duration = '1s'
-- auto_explain.log_analyze = true
-- auto_explain.log_buffers = true

-- 会话级启用
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '500ms';
SET auto_explain.log_analyze = true;

-- ============================================================
-- pg_stat_statements 扩展
-- ============================================================

-- 查看查询性能统计
SELECT query, calls, total_exec_time, mean_exec_time,
       rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- 注意：EXPLAIN 不执行查询，EXPLAIN ANALYZE 会实际执行
-- 注意：对 DML 使用 EXPLAIN ANALYZE 时需要用事务包裹并回滚
-- 注意：BUFFERS 选项需要与 ANALYZE 一起使用
-- 注意：cost 是无单位的估算值，不同查询间可比较
-- 注意：估算行数不准时，需要 ANALYZE 更新统计信息
-- 注意：auto_explain 扩展可自动记录慢查询计划
