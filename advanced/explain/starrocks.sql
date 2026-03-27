-- StarRocks: 执行计划与查询分析
--
-- 参考资料:
--   [1] StarRocks Documentation - EXPLAIN
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/Administration/EXPLAIN/
--   [2] StarRocks Documentation - Query Profile
--       https://docs.starrocks.io/docs/administration/query_profile_overview/

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 选项
-- ============================================================

-- 普通计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- 详细计划
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;

-- 成本信息
EXPLAIN COSTS SELECT * FROM users WHERE age > 25;

-- 逻辑计划
EXPLAIN LOGICAL SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN ANALYZE（3.0+）
-- ============================================================

EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 执行计划关键操作
-- ============================================================

-- OlapScanNode         OLAP 表扫描
-- ExchangeNode         数据交换
-- HashJoinNode         哈希连接
-- AggregationNode      聚合
-- SortNode             排序
-- AnalyticEvalNode     窗口函数
-- ProjectNode          投影
-- DecodeNode           字典解码
-- TopNNode             Top N

-- 分布方式：
-- BROADCAST            广播
-- SHUFFLE              按键 Shuffle
-- GATHER               汇集到一个节点
-- BUCKET_SHUFFLE       按桶 Shuffle（colocation）

-- ============================================================
-- Query Profile
-- ============================================================

-- 启用 Profile
SET enable_profile = true;

-- 执行查询后在 FE Web UI 查看
-- http://fe_host:8030/query

-- Profile 内容：
-- - Fragment 执行详情
-- - 各操作符的计时和统计
-- - Pipeline 调度信息
-- - 内存和 I/O 统计

-- ============================================================
-- 向量化引擎分析
-- ============================================================

-- StarRocks 使用全面向量化引擎
-- Pipeline 执行模型（3.0+）
-- Profile 中的 Pipeline 信息：
-- - DriverTotalTime   驱动器总时间
-- - ScheduleTime      调度时间
-- - PendingTime       挂起时间

-- ============================================================
-- 物化视图命中分析
-- ============================================================

-- 检查是否命中物化视图
EXPLAIN SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

-- 如果命中：OlapScanNode 的 TABLE 显示物化视图名

-- ============================================================
-- 统计信息
-- ============================================================

-- 手动收集
ANALYZE TABLE users;
ANALYZE FULL TABLE users;  -- 全量收集

-- 自动收集（默认启用）
SHOW ANALYZE STATUS;

-- 查看统计信息
SHOW COLUMN STATS users;

-- 注意：StarRocks EXPLAIN 显示向量化执行计划
-- 注意：3.0+ 使用 Pipeline 执行引擎，Profile 更详细
-- 注意：EXPLAIN COSTS 显示优化器的成本估算
-- 注意：BUCKET_SHUFFLE 利用 Colocation 避免网络传输
-- 注意：物化视图自动改写可以加速聚合查询
-- 注意：自动统计信息收集默认启用
