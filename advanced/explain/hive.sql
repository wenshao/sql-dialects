-- Hive: 执行计划与查询分析 (EXPLAIN)
--
-- 参考资料:
--   [1] Apache Hive Documentation - EXPLAIN
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Explain
--   [2] Apache Hive - Cost Based Optimization
--       https://cwiki.apache.org/confluence/display/Hive/Cost-based+optimization+in+Hive

-- ============================================================
-- 1. EXPLAIN 基本用法
-- ============================================================
EXPLAIN SELECT * FROM users WHERE age > 25;

-- EXPLAIN 输出结构:
-- STAGE DEPENDENCIES: 阶段依赖关系（DAG）
-- STAGE PLANS: 每个阶段的操作符树
--
-- Hive 的 EXPLAIN 与 RDBMS 的核心差异:
-- RDBMS (MySQL/PG): 展示操作符树（Seq Scan → Filter → Sort）
-- Hive:             展示 MapReduce/Tez 阶段 DAG + 每阶段内的操作符树
-- 本质上 Hive 是两级执行计划: 阶段级（Stage DAG）+ 操作符级（Operator Tree）

-- ============================================================
-- 2. EXPLAIN 变种
-- ============================================================
-- 扩展信息（包含文件路径、SerDe 等详细信息）
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;

-- 依赖分析（输入表和分区）
EXPLAIN DEPENDENCY SELECT * FROM users WHERE age > 25;

-- 权限检查
EXPLAIN AUTHORIZATION SELECT * FROM users WHERE age > 25;

-- 向量化信息（Hive 0.14+）
EXPLAIN VECTORIZATION SELECT * FROM users WHERE age > 25;
EXPLAIN VECTORIZATION DETAIL
SELECT age, COUNT(*) FROM users GROUP BY age;

-- CBO 计划（Hive 4.0+，展示 Calcite 优化器的逻辑计划）
EXPLAIN CBO SELECT * FROM users WHERE age > 25;

-- 抽象语法树
EXPLAIN AST SELECT * FROM users WHERE age > 25;

-- 设计分析: 多种 EXPLAIN 的意义
-- Hive 的执行链路长且复杂:
--   HiveQL → Parser(AST) → Semantic Analyzer → Logical Plan
--   → CBO(Calcite) → Physical Plan → Tez DAG → 执行
-- 每个 EXPLAIN 变种展示不同阶段的信息，帮助开发者定位性能问题所在。

-- ============================================================
-- 3. 复杂查询的执行计划解读
-- ============================================================
EXPLAIN
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.age > 25
GROUP BY u.username;

-- 典型输出结构（Tez 引擎）:
-- STAGE DEPENDENCIES:
--   Stage-1 is a root stage        ← Tez DAG
--   Stage-0 depends on stages: Stage-1
--
-- STAGE PLANS:
--   Stage-1
--     Tez
--       Vertices:
--         Map 1:                   ← 读取 users 表，过滤 age > 25
--           TableScan → Filter → Map Join
--         Map 2:                   ← 读取 orders 表
--           TableScan → Map Join
--         Reducer 3:               ← Group By 聚合
--           Group By → File Output
--   Stage-0
--     Fetch Operator               ← 返回结果

-- ============================================================
-- 4. 关键操作符解读
-- ============================================================
-- TableScan           表扫描（对应 HDFS 文件读取）
-- Select Operator     列投影（选择需要的列）
-- Filter Operator     行过滤（WHERE 条件）
-- Map Join Operator   Map 端 JOIN（小表广播）
-- Reduce Output Op    Shuffle 数据分发（按 key 分区）
-- Group By Operator   分组聚合
-- File Output Op      写入结果文件
-- Fetch Operator      客户端获取结果
-- Lateral View        LATERAL VIEW 展开
-- Union               UNION 操作

-- ============================================================
-- 5. 执行引擎选择
-- ============================================================
SET hive.execution.engine = tez;     -- 推荐（Hive 2.0+ 默认）
-- SET hive.execution.engine = spark; -- Hive on Spark
-- SET hive.execution.engine = mr;    -- MapReduce（已废弃）

-- Tez vs MapReduce 的核心差异:
-- MapReduce: 每个阶段写磁盘 → 下一阶段从磁盘读 → 串行链式执行
-- Tez:       DAG 执行，中间结果可以在内存中传递，多个阶段可以合并
-- 结果: Tez 比 MR 快 3-10 倍（典型 ETL 场景）

-- ============================================================
-- 6. 统计信息与 CBO
-- ============================================================
-- CBO（Cost-Based Optimizer，Hive 0.14+）依赖统计信息做出优化决策

-- 收集表级统计信息
ANALYZE TABLE users COMPUTE STATISTICS;

-- 收集列级统计信息（CBO 更精确的估算）
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, email, age;

-- 收集分区级统计信息
ANALYZE TABLE orders PARTITION (dt='2024-01-15') COMPUTE STATISTICS;

-- 查看统计信息
DESCRIBE FORMATTED users;
DESCRIBE EXTENDED users;

-- 启用 CBO
SET hive.cbo.enable = true;
SET hive.compute.query.using.stats = true;
SET hive.stats.fetch.column.stats = true;

-- CBO 的优化能力:
-- 1. JOIN 顺序优化: 根据表大小选择最优 JOIN 顺序
-- 2. JOIN 策略选择: Map Join vs Sort-Merge Join
-- 3. 分区裁剪: 利用分区统计信息跳过空分区
-- 4. 谓词下推: 将过滤条件推到扫描层

-- ============================================================
-- 7. 向量化执行
-- ============================================================
SET hive.vectorized.execution.enabled = true;
SET hive.vectorized.execution.reduce.enabled = true;

-- 向量化执行: 一次处理 1024 行（批量操作），而不是逐行处理
-- 性能提升: 2-5 倍（取决于查询类型）
-- 限制: 不是所有操作符都支持向量化（EXPLAIN VECTORIZATION 可以检查）

-- ============================================================
-- 8. 跨引擎对比: EXPLAIN 设计
-- ============================================================
-- 引擎           EXPLAIN 输出格式         执行模型
-- Hive           Stage DAG + 操作符树    MapReduce/Tez/Spark 阶段
-- MySQL          表格式（id/type/key）   单机迭代器模型
-- PostgreSQL     树形（Seq Scan→...）    单机迭代器模型，带代价估算
-- Spark SQL      Physical Plan 树        DAG + Stage
-- BigQuery       Slot 分配 + Stage 统计  无 EXPLAIN（只有执行后统计）
-- Trino          Fragment + Stage        分布式 Pipeline
-- ClickHouse     操作符树 + Pipeline     列式批处理
-- Flink SQL      DAG（StreamGraph）      流处理 DAG

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================
-- 1. EXPLAIN 是引擎可观测性的基础: 用户排查性能问题的第一工具
-- 2. 多级 EXPLAIN 很有价值: Hive 的 EXPLAIN/EXTENDED/VECTORIZATION/CBO
--    分别回答不同层面的问题（执行计划、物理细节、向量化、优化器决策）
-- 3. 统计信息决定 CBO 质量: 没有 ANALYZE TABLE，CBO 的估算可能完全错误
--    Hive 的教训: 很多用户不知道需要先 ANALYZE TABLE 才能让 CBO 生效
-- 4. 向量化执行是分析引擎的标配: Hive 的向量化执行证明了批量处理的性能优势
