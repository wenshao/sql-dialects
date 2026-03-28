-- Spark SQL: 执行计划与查询分析 (EXPLAIN)
--
-- 参考资料:
--   [1] Spark SQL - EXPLAIN
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-explain.html
--   [2] Spark SQL - Performance Tuning
--       https://spark.apache.org/docs/latest/sql-performance-tuning.html
--   [3] Spark SQL - Adaptive Query Execution
--       https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution

-- ============================================================
-- 1. EXPLAIN 语法
-- ============================================================

-- 默认模式: 只显示物理计划
EXPLAIN SELECT * FROM users WHERE age > 25;

-- FORMATTED: 格式化输出物理计划（更易读）
EXPLAIN FORMATTED SELECT * FROM users WHERE age > 25;

-- EXTENDED: 显示完整的四层计划（逻辑 -> 物理）
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;

-- CODEGEN: 显示 Tungsten 生成的 Java 代码
EXPLAIN CODEGEN SELECT * FROM users WHERE age > 25;

-- COST: 显示成本估算信息（Spark 3.0+）
EXPLAIN COST SELECT * FROM users WHERE age > 25;

-- ============================================================
-- 2. 四层计划体系: Catalyst 优化器的核心
-- ============================================================

EXPLAIN EXTENDED
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC;

-- EXPLAIN EXTENDED 输出四个计划:
-- 1. Parsed Logical Plan:     SQL 解析后的原始逻辑计划（AST -> 逻辑计划）
-- 2. Analyzed Logical Plan:   绑定元数据后的逻辑计划（解析表名、列名、类型）
-- 3. Optimized Logical Plan:  规则优化后的逻辑计划（谓词下推、常量折叠等）
-- 4. Physical Plan:           物理执行计划（具体的 JOIN 策略、扫描方式等）
--
-- 设计分析: Catalyst 优化器的分层架构
--   Catalyst 采用"规则优化 + 成本优化"的分层设计:
--   - 规则优化（Rule-Based，在 Optimized Logical Plan 阶段）:
--     谓词下推、列裁剪、常量折叠、子查询解关联等——确定性变换，总是有益
--   - 成本优化（Cost-Based，在 Physical Plan 阶段）:
--     JOIN 策略选择、JOIN 顺序、聚合策略——需要统计信息（行数、列基数）
--
-- 对比:
--   MySQL:      EXPLAIN 显示执行计划（type/key/rows/Extra），8.0+ 支持 EXPLAIN ANALYZE
--   PostgreSQL: EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT/JSON) 最详细
--   Oracle:     DBMS_XPLAN.DISPLAY_CURSOR 显示实际执行计划
--   Hive:       EXPLAIN 类似但没有 Tungsten CodeGen 信息
--   Flink SQL:  EXPLAIN 显示流处理计划（StreamTableScan, Join 等）
--   Trino:      EXPLAIN (TYPE DISTRIBUTED) 显示分布式执行计划

-- ============================================================
-- 3. 物理计划关键操作符
-- ============================================================

-- FileScan parquet:          Parquet 文件扫描，显示下推的过滤条件
-- Filter:                    行过滤
-- Project:                   列投影
-- BroadcastHashJoin:         广播 Hash JOIN（小表广播到所有 Executor）
-- SortMergeJoin:             排序合并 JOIN（两表先排序再合并，最通用）
-- ShuffledHashJoin:          Shuffle Hash JOIN（先 Shuffle 再 Hash）
-- BroadcastNestedLoopJoin:   广播嵌套循环 JOIN（非等值 JOIN）
-- HashAggregate:             Hash 聚合（部分聚合 + 最终聚合）
-- Sort:                      排序
-- Exchange:                  数据交换（= Shuffle，分布式计算的核心开销）
-- WholeStageCodegen:         全阶段代码生成（Tungsten 优化标志）
-- InMemoryTableScan:         内存表扫描（缓存的表）
-- SubqueryBroadcast:         子查询广播

-- WholeStageCodegen 是 Tungsten 执行引擎的标志:
--   传统执行: 每个操作符是独立的迭代器，存在虚函数调用开销
--   CodeGen:  将多个操作符融合为单个 Java 方法，编译为字节码执行
--   效果:     减少 CPU 缓存失效，减少虚函数调用，性能提升 2-10 倍
--
-- 对比:
--   ClickHouse: 也有类似的 LLVM JIT 代码生成
--   DuckDB:     向量化执行（不做代码生成，但减少虚函数调用）
--   Trino:      部分支持代码生成

-- ============================================================
-- 4. AQE: 自适应查询执行（Spark 3.0+）
-- ============================================================

SET spark.sql.adaptive.enabled = true;           -- 启用 AQE

-- AQE 的三大能力:

-- (1) 动态合并 Shuffle 分区（减少小分区数量）
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.coalescePartitions.minPartitionSize = 1048576;  -- 1MB

-- (2) 动态切换 JOIN 策略（运行时发现小表则自动 Broadcast）
SET spark.sql.adaptive.localShuffleReader.enabled = true;

-- (3) 动态优化倾斜 JOIN（自动拆分倾斜分区）
SET spark.sql.adaptive.skewJoin.enabled = true;
SET spark.sql.adaptive.skewJoin.skewedPartitionFactor = 5;

-- AQE 是 Spark SQL 最重要的运行时优化特性:
--   传统优化器（CBO）: 在查询开始前基于统计信息选择执行计划（静态）
--   AQE:               在查询执行过程中收集实际数据统计信息，动态调整计划（动态）
--   解决的核心问题:    统计信息不准确时（过时/缺失），CBO 选择错误计划
--
-- 对引擎开发者的启示:
--   AQE 代表了查询优化器的未来方向——运行时重优化。
--   但实现复杂度极高: 需要在 Stage 边界（Shuffle）处插入重优化点，
--   并在不影响已完成 Stage 的前提下修改后续 Stage 的计划。
--   类似的思路: Oracle 的 Adaptive Plans、SQL Server 的 Adaptive Query Processing。

-- ============================================================
-- 5. 查询 Hint
-- ============================================================

-- 广播 JOIN Hint（最常用的性能优化手段）
SELECT /*+ BROADCAST(u) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- Shuffle Hash JOIN Hint
SELECT /*+ SHUFFLE_HASH(o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- Sort Merge JOIN Hint
SELECT /*+ MERGE(u, o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- 数据倾斜 Hint（Spark 3.0+）
SELECT /*+ SKEW('orders') */ * FROM orders;

-- 合并小文件 Hint（Spark 3.0+）
SELECT /*+ COALESCE(5) */ * FROM orders;
SELECT /*+ REPARTITION(10, user_id) */ * FROM orders;

-- ============================================================
-- 6. 统计信息收集
-- ============================================================

ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, age;
ANALYZE TABLE orders COMPUTE STATISTICS FOR ALL COLUMNS;

DESCRIBE EXTENDED users;

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- Spark 2.0: EXPLAIN, CBO 基础
-- Spark 3.0: AQE, EXPLAIN COST, 动态分区裁剪, JOIN Hint 扩展
-- Spark 3.2: AQE 增强（自定义 Shuffle 读取优化）
-- Spark 3.4: EXPLAIN 输出改进
-- Spark 4.0: AQE 默认行为优化
--
-- 限制:
--   无 EXPLAIN ANALYZE（不能显示实际执行统计，需查看 Spark UI）
--   Spark UI 的 SQL 页面是最重要的性能分析工具（比 EXPLAIN 更详细）
--   Exchange 操作符 = Shuffle = 分布式计算的主要开销（优化核心）
