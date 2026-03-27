-- MariaDB: 执行计划与查询分析
--
-- 参考资料:
--   [1] MariaDB Documentation - EXPLAIN
--       https://mariadb.com/kb/en/explain/
--   [2] MariaDB Documentation - ANALYZE Statement
--       https://mariadb.com/kb/en/analyze-statement/
--   [3] MariaDB Documentation - Optimizer
--       https://mariadb.com/kb/en/query-optimizer/

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE username = 'alice';

-- 等价写法
DESCRIBE SELECT * FROM users WHERE username = 'alice';

-- ============================================================
-- EXPLAIN 输出格式
-- ============================================================

-- 传统格式
EXPLAIN SELECT * FROM users WHERE age > 25;

-- JSON 格式（10.1+，含成本信息和优化器细节）
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE age > 25;

-- ============================================================
-- ANALYZE（MariaDB 特有，10.1+）
-- ============================================================

-- 类似 MySQL 的 EXPLAIN ANALYZE，但 MariaDB 语法不同
ANALYZE SELECT * FROM users WHERE age > 25;

-- ANALYZE 输出额外包含：
-- r_rows:    实际返回行数
-- r_filtered: 实际过滤百分比
-- r_total_time_ms: 实际耗时

-- JSON 格式
ANALYZE FORMAT=JSON SELECT u.*, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;

-- ============================================================
-- EXPLAIN 用于 DML
-- ============================================================

EXPLAIN UPDATE users SET age = 30 WHERE username = 'alice';
EXPLAIN DELETE FROM users WHERE age < 18;
EXPLAIN INSERT INTO users (username, email) VALUES ('test', 'test@example.com');

-- ============================================================
-- EXPLAIN EXTENDED（已废弃但仍可用）
-- ============================================================

-- 显示额外的 filtered 列和优化后的查询
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;
SHOW WARNINGS;  -- 显示优化器重写后的查询

-- 10.1+: EXTENDED 是默认行为，不需要显式指定

-- ============================================================
-- EXPLAIN PARTITIONS
-- ============================================================

-- 显示查询涉及的分区
EXPLAIN PARTITIONS SELECT * FROM orders WHERE order_date >= '2024-01-01';

-- 10.1+: 分区信息默认包含

-- ============================================================
-- 优化器跟踪（10.1+）
-- ============================================================

SET optimizer_trace = 'enabled=on';
SELECT * FROM users WHERE age > 25 AND status = 1;
SELECT * FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';

-- ============================================================
-- 慢查询日志
-- ============================================================

-- 查看慢查询设置
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- 启用慢查询日志
SET GLOBAL slow_query_log = 1;
SET GLOBAL long_query_time = 1;        -- 1 秒
SET GLOBAL log_slow_verbosity = 'query_plan,explain';  -- 10.0+

-- ============================================================
-- Performance Schema
-- ============================================================

SELECT EVENT_NAME, COUNT_STAR, SUM_TIMER_WAIT/1000000000 AS total_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- ============================================================
-- 执行计划关键指标
-- ============================================================

-- type 列（从好到差）：
-- system    表只有一行
-- const     主键/唯一索引常量匹配
-- eq_ref    连接使用主键/唯一索引
-- ref       使用非唯一索引
-- range     索引范围扫描
-- index     索引全扫描
-- ALL       全表扫描

-- Extra 列重要信息：
-- Using index              覆盖索引
-- Using where              WHERE 过滤
-- Using temporary          临时表
-- Using filesort           文件排序
-- Using index condition    索引条件下推（ICP）
-- Using join buffer        连接缓冲区（Block Nested Loop / BNL / BKA）

-- ============================================================
-- MariaDB 特有优化器功能
-- ============================================================

-- 优化器开关
SHOW VARIABLES LIKE 'optimizer_switch'\G

-- 调整特定优化
SET optimizer_switch='mrr=on';                    -- Multi-Range Read
SET optimizer_switch='join_cache_hashed=on';       -- Hash Join (10.4+)
SET optimizer_switch='condition_pushdown_for_derived=on';

-- 直方图统计（10.0+）
ANALYZE TABLE users PERSISTENT FOR COLUMNS (age, status) INDEXES (idx_users_age);

-- 注意：MariaDB 用 ANALYZE 代替 MySQL 的 EXPLAIN ANALYZE
-- 注意：JSON 格式提供成本估算和优化器详细信息
-- 注意：MariaDB 10.1+ 的 EXPLAIN 默认包含 EXTENDED 和 PARTITIONS
-- 注意：log_slow_verbosity 可在慢查询日志中包含执行计划
-- 注意：MariaDB 有独立的查询优化器，与 MySQL 有一定差异
