# SQL 优化器演进

从固定规则到基于代价，再到运行时自适应，SQL 优化器经历了三代演进。优化器的质量直接决定了引擎的竞争力。

## 三代优化器

| 阶段 | 代表 | 时代 | 核心思路 | 典型引擎 |
|------|------|------|---------|---------|
| RBO | Rule-Based | 1970-1990 | 固定规则排序，索引优先 | Oracle 7-, MySQL 早期 |
| CBO | Cost-Based | 1990-2010 | 统计信息 + 代价模型 | Oracle 10g+, PostgreSQL, MySQL 8.0 |
| ABO | Adaptive/Autonomous | 2010-今 | 运行时反馈 + 自动调优 | Oracle 12c+, Spark AQE, TiDB |

## RBO: 基于规则的优化器

### 工作原理

```
RBO 按照一组固定优先级的规则选择执行计划。
不关心数据分布、表大小、索引选择性。

Oracle 的 RBO 规则优先级 (从高到低):
  1. ROWID 直接访问
  2. 唯一索引等值匹配
  3. 主键等值匹配
  4. 组合索引完全匹配
  5. 组合索引部分匹配
  6. 非唯一索引等值匹配
  7. 索引范围扫描
  8. 索引全扫描
  9. 全表扫描
  10. ...

规则: 如果查询条件可以使用规则 2 (唯一索引)，就一定使用，
      不管全表扫描是否可能更快 (比如表只有 10 行)。
```

### RBO 的致命缺陷

```sql
-- 场景: employees 表 100 万行, 99% 的人 status = 'active'
-- 索引: idx_status (status)

-- RBO 的选择:
SELECT * FROM employees WHERE status = 'active';
-- RBO: "有索引! 用索引!" -> 使用 idx_status
-- 实际: 索引返回 99 万行 -> 99 万次回表 -> 比全表扫描慢 10 倍!

-- 正确做法: 全表扫描 (顺序 I/O) 比索引回表 (随机 I/O) 快得多
-- 但 RBO 不知道 status = 'active' 覆盖 99% 的行

-- 另一个例子:
SELECT * FROM orders WHERE order_date > '2000-01-01';
-- idx_order_date 存在
-- RBO: 用索引范围扫描
-- 实际: 几乎所有订单都在 2000 年之后 -> 索引毫无用处
```

### 为什么 RBO 被淘汰

```
1. 无法感知数据分布:
   - 不知道 WHERE col = 'x' 会返回多少行
   - 不知道索引的选择性

2. 无法做 JOIN 排序:
   - 三表 JOIN 有 3! = 6 种顺序
   - RBO 只能按固定规则 (如表在 FROM 中的顺序)
   - 错误的 JOIN 顺序可能导致性能差 1000 倍

3. 无法权衡 I/O 类型:
   - 不区分顺序 I/O (全表扫描) 和随机 I/O (索引回表)
   - 不考虑缓冲池命中率

Oracle 在 10g (2003) 中废弃了 RBO，全面转向 CBO。
```

## CBO: 基于代价的优化器

### 核心架构

```
CBO 的工作流程:

1. 查询改写 (Rewrite):
   - 视图展开、子查询解关联、谓词下推
   - 不依赖统计信息的逻辑优化

2. 计划枚举 (Enumeration):
   - 生成所有可能的执行计划 (搜索空间)
   - 包括: 访问路径选择、JOIN 顺序、JOIN 算法

3. 代价估算 (Cost Estimation):
   - 基于统计信息估算每个计划的代价
   - 代价 = CPU + I/O + 网络 (分布式)

4. 计划选择 (Plan Selection):
   - 选择代价最低的执行计划

关键输入: 统计信息 (Statistics)
```

### 统计信息

#### 基础统计信息

```sql
-- 表级统计:
-- row_count: 行数
-- data_size: 数据大小 (字节)

-- 列级统计:
-- NDV (Number of Distinct Values): 不同值的数量
-- null_fraction: NULL 值的比例
-- avg_width: 平均列宽 (字节)
-- min/max: 最小值/最大值

-- 收集统计信息:
-- PostgreSQL:
ANALYZE table_name;
-- MySQL:
ANALYZE TABLE table_name;
-- Oracle:
EXEC DBMS_STATS.GATHER_TABLE_STATS('schema', 'table_name');
-- Spark:
ANALYZE TABLE table_name COMPUTE STATISTICS FOR ALL COLUMNS;
```

#### 直方图 (Histogram)

```sql
-- 直方图记录列值的分布，是 CBO 最重要的统计信息

-- 等宽直方图 (Equi-Width):
-- 将值域等分为 N 个桶，记录每个桶的频率
-- 问题: 数据倾斜时某些桶包含大量值，信息丢失

-- 等深直方图 (Equi-Depth / Equi-Height):
-- 每个桶包含大约相同数量的行
-- PostgreSQL 使用: 最多 100 个桶 (default_statistics_target)
-- 能更好地表示数据倾斜

-- 例: 100 万行, status 列的等深直方图 (10 桶):
-- 桶 1: 'active' (freq: 500000)    <- 高频值单独成桶
-- 桶 2: 'inactive' (freq: 200000)
-- 桶 3-10: 其他值均匀分布

-- 高频值 (Most Common Values, MCV):
-- PostgreSQL: 单独记录最常见的 N 个值及其频率
SELECT most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'employees' AND attname = 'status';
-- most_common_vals: {active, inactive, pending}
-- most_common_freqs: {0.5, 0.2, 0.1}

-- Singleton 直方图 (Oracle):
-- 当 NDV 很少时，每个值一个桶
-- 例: status 列只有 5 种值 -> 5 个桶

-- Top-N 直方图 (Oracle 12c+):
-- 只记录出现频率最高的 N 个值
-- 其他值假设均匀分布
```

### 基数估算 (Cardinality Estimation)

```sql
-- 基数 = 操作符输出的行数估算

-- 等值过滤:
SELECT * FROM t WHERE col = 'x';
-- 估算: row_count * (1 / NDV)     (假设均匀分布)
-- 有直方图: row_count * freq('x')  (更准确)

-- 范围过滤:
SELECT * FROM t WHERE col BETWEEN 10 AND 20;
-- 估算: row_count * (20 - 10) / (max - min)  (假设均匀分布)
-- 有直方图: 累加范围内各桶的频率

-- AND 组合:
SELECT * FROM t WHERE a = 1 AND b = 2;
-- 估算: row_count * sel(a=1) * sel(b=2)  (假设独立性)
-- 独立性假设常常不成立! 例: city='北京' AND province='北京市'
-- 相关列的估算是 CBO 最大的挑战之一

-- JOIN 基数:
SELECT * FROM a JOIN b ON a.id = b.id;
-- 估算: |a| * |b| / max(NDV(a.id), NDV(b.id))
-- 即: 较大的 NDV 决定了 JOIN 的选择性
```

### JOIN 优化

#### JOIN Reordering (重排序)

```sql
-- N 表 JOIN 有 N! 种顺序
-- 3 表: 6 种, 5 表: 120 种, 10 表: 3628800 种!

-- 策略 1: 穷举 (小 N)
-- PostgreSQL: N <= 11 时穷举所有顺序 (geqo_threshold)
-- MySQL: N <= 61 时使用贪心算法

-- 策略 2: 遗传算法 (大 N, PostgreSQL GEQO)
-- PostgreSQL 的 GEQO (Genetic Query Optimizer):
-- N > 11 时自动启用
-- 用遗传算法搜索 JOIN 顺序
-- 不保证最优，但能在合理时间内给出较好的计划
SET geqo_threshold = 12;      -- 控制何时启用 GEQO
SET geqo_effort = 5;          -- 搜索努力程度 (1-10)

-- 策略 3: 动态规划 (经典方法)
-- 自底向上构建最优 JOIN 树
-- 先计算所有两表 JOIN 的最优计划
-- 再计算三表 JOIN (基于两表的最优)
-- 时间复杂度: O(3^N), 空间: O(2^N)

-- 策略 4: 启发式 (MySQL)
-- MySQL 的优化器使用贪心 + 有限搜索
-- 每步选择当前代价最低的表加入
-- 通过 optimizer_search_depth 控制搜索深度
SET optimizer_search_depth = 0;  -- 自动选择深度
```

#### JOIN 算法选择

```
三种基本 JOIN 算法:

1. Nested Loop Join (嵌套循环):
   代价: O(|R| * |S|)
   适用: 内表很小或有索引
   优点: 支持任意 JOIN 条件

2. Hash Join (哈希连接):
   代价: O(|R| + |S|)  (构建 + 探测)
   适用: 等值 JOIN, 内表可放入内存
   优点: 等值 JOIN 最快

3. Sort-Merge Join (排序合并):
   代价: O(|R|log|R| + |S|log|S| + |R| + |S|)
   适用: 等值 JOIN, 数据已排序或需要排序输出
   优点: 不需要额外内存 (如果已排序)

CBO 根据估算的行数和可用内存选择算法:
  - 内表 < hash_mem -> Hash Join
  - 两表都很大且需排序输出 -> Sort-Merge Join
  - 内表有索引 -> Index Nested Loop Join
```

### Predicate Pushdown (谓词下推)

```sql
-- 将过滤条件尽可能推到靠近数据源的位置

-- 优化前:
SELECT * FROM (
    SELECT a.*, b.name
    FROM orders a JOIN customers b ON a.cust_id = b.id
) t
WHERE t.name = 'Alice';

-- 优化后 (谓词下推到 JOIN 内部):
SELECT a.*, b.name
FROM orders a
JOIN (SELECT * FROM customers WHERE name = 'Alice') b
ON a.cust_id = b.id;

-- 效果: customers 先过滤再 JOIN, 减少 JOIN 的数据量

-- 谓词下推到存储层:
-- 列式存储 (Parquet/ORC): 推到列的 min/max 统计信息过滤
-- 分区表: 推到分区裁剪
-- 外部表: 推到数据源 (如 JDBC 推到远端数据库)
```

## 各引擎的优化器特点

### PostgreSQL 优化器

```sql
-- PostgreSQL 优化器特点:
-- 1. 经典的 CBO, 社区维护数十年
-- 2. GEQO 处理大量表的 JOIN
-- 3. 支持自定义统计对象 (相关列统计)
-- 4. 不支持 hints (哲学: 优化器应该比人聪明)

-- 扩展统计: 解决相关列的估算问题
CREATE STATISTICS s1 (dependencies) ON city, province FROM addresses;
ANALYZE addresses;
-- 优化器现在知道 city 和 province 是相关的

-- 查看执行计划:
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;
-- 显示: 预估行数 vs 实际行数, 缓冲命中, 时间
```

### MySQL 优化器

```sql
-- MySQL 优化器特点:
-- 1. 从 RBO 逐步演进到 CBO (5.7/8.0)
-- 2. 支持 optimizer hints (与 Oracle 类似)
-- 3. cost model 可配置 (mysql.server_cost, mysql.engine_cost)
-- 4. 直到 8.0.18 才支持 Hash Join

-- Optimizer Hints:
SELECT /*+ JOIN_ORDER(a, b, c) */ a.*, b.*, c.*
FROM a JOIN b ON ... JOIN c ON ...;

SELECT /*+ NO_INDEX(t idx_name) */ * FROM t WHERE ...;

SELECT /*+ BNL(t1, t2) */ ...;   -- Block Nested Loop (8.0 前)
SELECT /*+ HASH_JOIN(t1, t2) */ ...;  -- Hash Join (8.0.18+)

-- 查看优化器开关:
SELECT @@optimizer_switch;
-- index_merge=on, mrr=on, batched_key_access=off, ...
SET optimizer_switch = 'hash_join=on';

-- Cost Model 配置:
UPDATE mysql.server_cost SET cost_value = 0.1 WHERE cost_name = 'row_evaluate_cost';
UPDATE mysql.engine_cost SET cost_value = 1.0 WHERE cost_name = 'io_block_read_cost';
FLUSH OPTIMIZER_COSTS;
```

### Oracle 优化器

```sql
-- Oracle 优化器特点:
-- 1. 业界最成熟的 CBO
-- 2. 丰富的 hints 系统 (200+ hints)
-- 3. SQL Plan Management (SPM): 计划稳定性
-- 4. Adaptive Plans (12c+): 运行时调整

-- Hints (Oracle 最著名的特性之一):
SELECT /*+ FULL(t) */ * FROM employees t;           -- 强制全表扫描
SELECT /*+ INDEX(t idx_name) */ * FROM employees t;  -- 强制使用索引
SELECT /*+ LEADING(a b c) */ ...;                    -- 指定 JOIN 顺序
SELECT /*+ USE_HASH(a b) */ ...;                     -- 使用 Hash Join
SELECT /*+ PARALLEL(t, 4) */ * FROM big_table t;     -- 并行查询

-- SQL Plan Management:
-- 将"好"的执行计划固定下来，防止统计信息变化后计划退化
-- 类似 PostgreSQL 的 pg_hint_plan 但更系统化

-- Adaptive Plans (12c+):
-- 执行计划包含"决策点"
-- 运行时根据实际数据量选择分支
-- 例: 先尝试 Nested Loop, 如果行数超过阈值, 切换到 Hash Join
```

## ABO: 自适应/自治优化器

### 运行时自适应

```sql
-- Spark AQE (Adaptive Query Execution):
SET spark.sql.adaptive.enabled = true;

-- AQE 在运行时做以下调整:
-- 1. 动态合并 Shuffle 分区
--    如果某个分区太小, 自动合并相邻分区
SET spark.sql.adaptive.coalescePartitions.enabled = true;

-- 2. 动态切换 JOIN 策略
--    如果运行时发现一表很小, 从 Shuffle JOIN 切换到 Broadcast JOIN
SET spark.sql.adaptive.localShuffleReader.enabled = true;

-- 3. 动态处理数据倾斜
SET spark.sql.adaptive.skewJoin.enabled = true;

-- Oracle Adaptive Plans (12c+):
-- 运行时在 Nested Loop 和 Hash Join 之间切换
-- 基于 STATISTICS COLLECTOR 操作符收集的实际行数
-- 如果实际行数远超预估, 切换到 Hash Join
```

### 自动统计信息管理

```sql
-- Oracle 自动统计收集:
-- 默认在维护窗口 (夜间) 自动 ANALYZE 所有表
-- DBMS_AUTO_TASK 管理

-- PostgreSQL autovacuum:
-- 自动 ANALYZE (与 VACUUM 一起运行)
-- 当表变更行数超过阈值时触发
-- autovacuum_analyze_threshold = 50 (最小变更行数)
-- autovacuum_analyze_scale_factor = 0.1 (变更比例)

-- TiDB 自动统计:
-- 自动检测统计信息过时并重新收集
SET tidb_enable_auto_analyze = ON;
```

### 学习型优化器

```
前沿方向: 用机器学习改进 CBO

1. 基数估算的 ML 模型:
   - 用历史查询的实际基数训练模型
   - 替代传统的独立性假设和直方图
   - 学术项目: Naru, DeepDB, MSCN

2. 索引推荐:
   - 分析 workload, 推荐最优索引组合
   - Oracle: SQL Access Advisor
   - PostgreSQL: pg_qualstats + HypoPG
   - MySQL: 无内置工具, 第三方: Percona Toolkit

3. 计划回归检测:
   - 自动检测计划变差 (性能回退)
   - Oracle SPM: 自动捕获和比较计划
   - SQL Server: Query Store
```

## 对引擎开发者: CBO 是现代引擎的标配

### 最小可行 CBO

```
构建 CBO 的最小需求:

1. 统计信息存储:
   - 表级: row_count, data_size
   - 列级: NDV, null_fraction, min, max
   - (可选) 直方图

2. 基数估算器:
   - 等值过滤: rows * (1/NDV)
   - 范围过滤: rows * (range / value_range)
   - AND: sel(a) * sel(b) (独立性假设)
   - OR: sel(a) + sel(b) - sel(a) * sel(b)
   - JOIN: |R| * |S| / max(NDV_R, NDV_S)

3. 代价模型:
   - Table Scan 代价: pages * io_cost
   - Index Scan 代价: matching_rows * random_io_cost
   - Sort 代价: rows * log(rows) * cpu_cost
   - Hash Join 代价: (build_rows + probe_rows) * cpu_cost + build_rows * mem_cost

4. 计划枚举:
   - 对于 N <= 10 的 JOIN: 动态规划
   - 对于 N > 10: 贪心或遗传算法

5. 统计信息收集:
   - ANALYZE TABLE 命令
   - 采样: 不需要全表扫描，随机采样估算 NDV 和分布
```

### 优化器开发路线图

```
阶段 1: 基础 RBO (可用)
  - 谓词下推
  - 列裁剪
  - 常量折叠
  - 简单的索引选择 (有索引就用)

阶段 2: 基础 CBO (可靠)
  - 统计信息收集和存储
  - 基数估算
  - 代价模型
  - JOIN 算法选择 (NLJ vs Hash Join)

阶段 3: 高级 CBO (高性能)
  - JOIN 重排序
  - 子查询优化 (去关联化)
  - 物化视图匹配
  - 并行查询优化
  - 直方图和相关列统计

阶段 4: 自适应优化 (卓越)
  - 运行时计划调整
  - 查询反馈 (actual vs estimated)
  - 自动统计信息管理
  - 计划缓存和复用
```

## 参考资料

- Selinger et al.: "Access Path Selection in a Relational Database Management System" (1979, 奠基论文)
- PostgreSQL: [Planner/Optimizer](https://www.postgresql.org/docs/current/planner-optimizer.html)
- Oracle: [Query Optimizer Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/)
- MySQL: [Query Optimization](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- Spark: [Adaptive Query Execution](https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution)
- CMU 15-721: [Advanced Database Systems - Query Optimization](https://15721.courses.cs.cmu.edu/)
