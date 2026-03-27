-- Apache Doris: 执行计划与查询分析
--
-- 参考资料:
--   [1] Doris Documentation - EXPLAIN
--       https://doris.apache.org/docs/sql-manual/sql-statements/Utility-Statements/EXPLAIN
--   [2] Doris Documentation - Query Analysis
--       https://doris.apache.org/docs/admin-manual/query-profile

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 详细级别
-- ============================================================

-- 普通计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- 详细计划
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;

-- 显示分布式执行计划
EXPLAIN GRAPH SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN ANALYZE（2.0+）
-- ============================================================

-- 实际执行并收集统计
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- OlapScanNode         OLAP 表扫描（前缀索引、Zone Map 等）
-- Exchange             数据交换（节点间传输）
-- HashJoinNode         哈希连接
-- AggregationNode      聚合
-- SortNode             排序
-- AnalyticEvalNode     分析函数
-- UnionNode            联合
-- AssertNumRowsNode    断言行数
-- SelectNode           选择/过滤
-- DataStreamSink       数据流输出

-- 分布方式：
-- BROADCAST            广播
-- HASH_PARTITIONED     哈希分区
-- UNPARTITIONED        不分区（汇集）

-- ============================================================
-- Query Profile
-- ============================================================

-- 启用 Profile
SET enable_profile = true;

-- 执行查询后查看 Profile
-- 方式 1：Doris FE Web UI（默认端口 8030）
-- 方式 2：API
-- curl http://fe_host:8030/api/profile?query_id=xxx

-- Profile 包含：
-- - 每个 Fragment 的执行时间
-- - 每个操作符的行数、时间
-- - I/O 统计
-- - 内存使用
-- - 网络传输

-- ============================================================
-- 查询统计
-- ============================================================

-- 查看正在执行的查询
SHOW PROCESSLIST;

-- 查看查询 Profile 列表
SHOW QUERY PROFILE "/";

-- 查看特定查询的 Profile
SHOW QUERY PROFILE "/query_id";

-- ============================================================
-- 统计信息
-- ============================================================

-- 收集统计信息
ANALYZE TABLE users;
ANALYZE TABLE users WITH SYNC;  -- 同步收集
ANALYZE TABLE users (username, age);  -- 指定列

-- 查看统计信息
SHOW COLUMN STATS users;
SHOW TABLE STATS users;

-- ============================================================
-- 关键优化指标
-- ============================================================

-- 1. 前缀索引命中：OlapScanNode 的 shortKeyFilterRatio
-- 2. Zone Map 过滤：通过 MIN/MAX 跳过数据块
-- 3. Bloom Filter：用于精确匹配过滤
-- 4. 物化视图命中：自动选择最佳物化视图

-- 检查物化视图命中
EXPLAIN SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;
-- 查看 rollup 是否被选中

-- 注意：Doris EXPLAIN 显示分布式执行计划
-- 注意：EXPLAIN GRAPH 以图形化方式展示执行计划
-- 注意：2.0+ 支持 EXPLAIN ANALYZE 获取实际执行统计
-- 注意：FE Web UI 提供 Query Profile 的图形化展示
-- 注意：前缀索引和 Zone Map 是 Doris 最重要的优化手段
-- 注意：自动物化视图选择可以显著加速聚合查询
