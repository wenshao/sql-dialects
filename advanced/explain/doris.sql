-- Apache Doris: 执行计划与查询分析
--
-- 参考资料:
--   [1] Doris Documentation - EXPLAIN / Query Profile
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. EXPLAIN 体系: MPP 分布式执行计划
-- ============================================================
-- Doris 的 EXPLAIN 输出与 MySQL 完全不同——因为它是分布式 MPP 引擎。
-- 执行计划展示的是 Fragment(执行片段) 和 Exchange(数据交换) 的拓扑。
--
-- 对比:
--   MySQL:      单机计划——Table Access/Nested Loop/Hash Join
--   Doris:      分布式计划——Fragment/Exchange/Shuffle/Broadcast
--   StarRocks:  与 Doris 类似(同源)，但 CBO 优化器更强
--   ClickHouse: 单机计划(Distributed 引擎透明处理分布式)
--   BigQuery:   EXPLAIN 显示 Stage(类似 Fragment)

-- ============================================================
-- 2. EXPLAIN 级别
-- ============================================================
EXPLAIN SELECT * FROM users WHERE age > 25;
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;
EXPLAIN GRAPH SELECT * FROM users WHERE age > 25;

-- EXPLAIN ANALYZE (2.0+): 实际执行并收集统计
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 3. 执行计划关键算子
-- ============================================================
-- OlapScanNode:       OLAP 表扫描(前缀索引、Zone Map 过滤)
-- Exchange:           数据交换(BROADCAST/HASH_PARTITIONED/UNPARTITIONED)
-- HashJoinNode:       哈希连接
-- AggregationNode:    聚合
-- SortNode:           排序
-- AnalyticEvalNode:   窗口函数
-- DataStreamSink:     数据流输出
--
-- 分布方式(Exchange 类型):
--   BROADCAST:         小表广播到所有节点(适合小表 JOIN)
--   HASH_PARTITIONED:  按 Hash 重分布(大表 JOIN)
--   UNPARTITIONED:     汇集到单节点(最终结果)

-- ============================================================
-- 4. Query Profile (性能分析)
-- ============================================================
SET enable_profile = true;

-- 执行查询后查看 Profile:
-- FE Web UI: http://fe_host:8030
-- API: curl http://fe_host:8030/api/profile?query_id=xxx

SHOW PROCESSLIST;                       -- 正在执行的查询
SHOW QUERY PROFILE "/";                 -- Profile 列表
SHOW QUERY PROFILE "/query_id";         -- 特定查询

-- ============================================================
-- 5. 统计信息 (Nereids 优化器，2.0+)
-- ============================================================
ANALYZE TABLE users;
ANALYZE TABLE users WITH SYNC;
ANALYZE TABLE users (username, age);
SHOW COLUMN STATS users;
SHOW TABLE STATS users;

-- 设计分析:
--   Doris 2.0 引入 Nereids 优化器(CBO)，统计信息的质量直接影响执行计划。
--   对比 StarRocks: CBO(Cascades 框架)从 1.x 就有，更成熟。
--   对比 MySQL:    ANALYZE TABLE 更新 InnoDB 统计信息。
--   对比 ClickHouse: 无 CBO，依赖规则优化器(RBO)。

-- ============================================================
-- 6. 关键优化指标
-- ============================================================
-- 前缀索引命中:    OlapScanNode 的 shortKeyFilterRatio
-- Zone Map 过滤:   通过 MIN/MAX 跳过数据块
-- Bloom Filter:    用于精确匹配过滤
-- 物化视图命中:    自动选择最佳 MV/ROLLUP

-- 检查物化视图命中
EXPLAIN SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

-- 对引擎开发者的启示:
--   MPP 执行计划的核心是 Exchange 策略选择:
--   Broadcast: O(小表大小 × 节点数) 网络开销
--   Shuffle:   O(大表大小) 网络开销
--   CBO 需要准确的表大小统计才能做出正确选择。
