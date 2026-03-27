-- Hive: 执行计划与查询分析
--
-- 参考资料:
--   [1] Apache Hive Documentation - EXPLAIN
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Explain
--   [2] Apache Hive Documentation - Tez
--       https://cwiki.apache.org/confluence/display/Hive/Hive+on+Tez

-- ============================================================
-- EXPLAIN 基本用法
-- ============================================================

EXPLAIN SELECT * FROM users WHERE age > 25;

-- 输出包含：
-- STAGE DEPENDENCIES: 阶段依赖关系
-- STAGE PLANS: 每个阶段的执行计划

-- ============================================================
-- EXPLAIN 选项
-- ============================================================

-- 扩展 EXPLAIN（包含额外信息）
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;

-- 依赖关系
EXPLAIN DEPENDENCY SELECT * FROM users WHERE age > 25;

-- 授权信息
EXPLAIN AUTHORIZATION SELECT * FROM users WHERE age > 25;

-- 向量化信息（Hive 0.14+）
EXPLAIN VECTORIZATION SELECT * FROM users WHERE age > 25;

-- CBO 计划（Hive 4.0+）
EXPLAIN CBO SELECT * FROM users WHERE age > 25;

-- AST（抽象语法树）
EXPLAIN AST SELECT * FROM users WHERE age > 25;

-- ============================================================
-- EXPLAIN 输出结构
-- ============================================================

EXPLAIN
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.age > 25
GROUP BY u.username;

-- 输出结构：
-- STAGE DEPENDENCIES:
--   Stage-1 is a root stage    ← MapReduce / Tez 阶段
--   Stage-0 depends on stages: Stage-1
--
-- STAGE PLANS:
--   Stage-1
--     Map/Reduce:
--       Map Operator Tree:
--         TableScan → Filter → Map Join → ...
--       Reduce Operator Tree:
--         Group By → ...
--   Stage-0
--     Fetch Operator

-- ============================================================
-- 执行计划关键操作符
-- ============================================================

-- TableScan          表扫描
-- Select Operator    选择/投影
-- Filter Operator    过滤
-- Map Join Operator  Map 端连接
-- Reduce Output Operator  Reduce 输出
-- Group By Operator  分组聚合
-- File Output Operator  文件输出
-- Fetch Operator     获取结果
-- Union              联合
-- Lateral View       侧视图

-- ============================================================
-- Tez / Spark 执行引擎
-- ============================================================

-- 设置执行引擎
SET hive.execution.engine=tez;     -- 默认（Hive 2.0+）
-- SET hive.execution.engine=spark;
-- SET hive.execution.engine=mr;    -- 已废弃

-- Tez 的执行计划用 Vertex（顶点）代替 Map/Reduce 阶段
EXPLAIN
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

-- ============================================================
-- 查询日志和性能
-- ============================================================

-- 查看查询执行历史（Hive 2.0+ LLAP）
SELECT * FROM sys.runtime_stats ORDER BY start_time DESC LIMIT 10;

-- HiveServer2 Web UI：
-- http://hiveserver2-host:10002/
-- 提供活跃查询和历史查询信息

-- ============================================================
-- 统计信息
-- ============================================================

-- 收集表统计信息
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS;

-- 查看统计信息
DESCRIBE FORMATTED users;
DESCRIBE EXTENDED users;

-- ============================================================
-- 向量化执行
-- ============================================================

-- 启用向量化（批量处理 1024 行）
SET hive.vectorized.execution.enabled = true;
SET hive.vectorized.execution.reduce.enabled = true;

-- 检查向量化是否生效
EXPLAIN VECTORIZATION DETAIL
SELECT age, COUNT(*) FROM users GROUP BY age;

-- ============================================================
-- CBO（基于成本的优化器，Hive 0.14+）
-- ============================================================

-- 启用 CBO
SET hive.cbo.enable = true;
SET hive.compute.query.using.stats = true;
SET hive.stats.fetch.column.stats = true;

-- 查看 CBO 计划
EXPLAIN CBO SELECT * FROM users WHERE age > 25;

-- 注意：Hive EXPLAIN 显示 MapReduce/Tez/Spark 阶段
-- 注意：EXPLAIN EXTENDED 提供最详细的信息
-- 注意：EXPLAIN VECTORIZATION 检查向量化执行是否生效
-- 注意：CBO 需要统计信息（ANALYZE TABLE）才能做出好的决策
-- 注意：Tez 引擎比 MapReduce 更高效，建议使用
-- 注意：EXPLAIN 不实际执行查询
