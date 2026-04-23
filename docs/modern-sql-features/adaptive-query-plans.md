# 自适应查询优化 (Adaptive Query Plans)

优化器在编译阶段根据统计信息生成的"最优"计划，往往在运行时被现实打脸——基数估计偏差一个数量级，就足以让 Nested Loop 退化成灾难、让 Broadcast Join 变成 OOM。自适应查询优化（Adaptive Query Plans, AQP / Adaptive Query Execution, AQE）是过去十年数据库内核最重要的设计思想之一：让计划在执行中**根据真实数据**自我修正。

## 没有 SQL 标准：纯粹的实现竞赛

与 `TABLESAMPLE`、`MERGE`、窗口函数等有明确标准定义的能力不同，自适应查询优化**不存在任何 SQL 标准规范**（ISO/IEC 9075 从未涉及）。它属于完全的"引擎内部实现细节"——用户可见的只有 EXPLAIN 输出中的 `adaptive` / `AQE` 标记，以及执行计划的动态变化。

这导致：

1. **术语混乱**：Oracle 叫 Adaptive Plans，SQL Server 叫 Adaptive Query Processing，Spark 叫 Adaptive Query Execution，DB2 叫 Learning Optimizer，含义各有侧重。
2. **能力边界不清**：同一个词（如"动态分区裁剪"）在不同引擎中可能是编译期裁剪也可能是运行期裁剪。
3. **行为不可移植**：同一条 SQL 在 Oracle 上会自动切换到 Hash Join，在 PostgreSQL 上永远不会，语义等价但性能差异可达 1000 倍。
4. **无法通过 SQL 显式开启**：大部分自适应能力靠会话参数 (`SET`)、查询 Hint 或初始化参数控制，而非 SQL 语法。

本文梳理 45+ 引擎的自适应能力分布、关键算法、版本时间线、以及对引擎开发者的实现启示。

## 为什么静态计划会失败

传统 CBO（Cost-Based Optimizer）的核心假设：

1. **统计信息准确**：表行数、列基数、直方图、相关性……都是"真相"
2. **数据分布均匀**：直方图能用 254 个 bucket 描述任意列
3. **谓词独立**：`WHERE a = 1 AND b = 2` 的选择率 = P(a=1) × P(b=2)
4. **Join 选择性可预测**：基于列直方图估算 Join 输出行数

现实中这些假设几乎**永远不成立**：

```sql
-- 经典案例 1：相关谓词
SELECT * FROM orders WHERE country = 'US' AND state = 'CA';
-- CBO 假设独立: 5% × 10% = 0.5%
-- 实际: 约 10%（CA 全在 US）, 估计低 20 倍
-- 后果: 选错 Nested Loop, 慢 100 倍

-- 经典案例 2：倾斜数据
SELECT * FROM events e JOIN users u ON e.user_id = u.id
WHERE e.event_time > CURRENT_DATE - 1;
-- CBO 估计: 每个 user_id 平均 10 个 event
-- 实际: 1% 的"bot 用户"各有 100 万 event (heavy hitter)
-- 后果: 单个 reducer 处理 1 亿行, job 挂住

-- 经典案例 3：过期统计
-- 统计信息最后更新于 3 个月前
-- 表已从 1M 行增长到 100M 行
-- CBO 基于 1M 行规划 Hash Join 内存分配
-- 后果: 执行时内存爆表，spill to disk 10 分钟
```

自适应查询优化的核心思路：**不相信编译期的估计，用运行期的真实数据持续修正**。具体手段因引擎而异，但可归纳为五大类：

1. **Runtime Plan Switching（运行时计划切换）**：在查询执行中途切换物理算子
2. **Adaptive Joins（自适应 Join）**：根据真实输入行数在 Nested Loop / Hash / Broadcast 之间切换
3. **Dynamic Partition Pruning（动态分区裁剪）**：在 Build 端得到真实值后裁剪 Probe 端分区
4. **Adaptive Statistics / Reoptimization（自适应统计与重优化）**：执行后反馈真实行数以修正后续查询
5. **Runtime Cardinality Feedback**：执行中途基于真实行数触发重规划

## 支持矩阵（综合）

### 核心能力支持对比（45 引擎）

| 引擎 | 运行时计划切换 | 自适应 Join (NL↔Hash) | 动态分区裁剪 | 自适应统计反馈 | 执行中重优化 | 起始版本 |
|------|---------------|----------------------|-------------|---------------|-------------|---------|
| Oracle | 是 | 是 | 是 (12c+) | 是 (Statistics Feedback) | 是 | 12c (2013) |
| SQL Server | 部分 | 是 (Adaptive Join) | 是 | 否 | 否 | 2017 |
| Spark SQL (AQE) | 是 | 是 (Broadcast 切换) | 是 (DPP) | 是 (stage 级) | 是 (stage 边界) | 3.0 (2020) |
| DB2 (LUW/z) | 是 (LEO) | 是 | 是 | 是 (REOPT) | 是 | V8 (2004) |
| PostgreSQL | 否 (原生) | 否 | 否 | 否 | 否 (需扩展) | -- |
| MySQL | 否 | 否 | 否 | 否 | 否 | -- |
| MariaDB | 否 | 否 | 否 | 否 | 否 | -- |
| SQLite | 否 | 否 | 否 | 否 | 否 | -- |
| Snowflake | 是 (内部) | 是 (内部) | 是 | 是 | 否 (公开) | 未公开版本 |
| Redshift | 部分 | 部分 | 是 | 是 (Adaptive Sort Spill) | 部分 | 2019+ |
| BigQuery | 是 (Dynamic Plan) | 是 | 是 (Dynamic Pruning) | 是 | 是 (阶段边界) | 持续演进 |
| Trino / Presto | 部分 | 部分 (Dynamic Filtering) | 是 | 否 | 否 | 346 (2020)+ |
| Impala | 部分 (Runtime Filters) | 否 (切换) | 是 | 否 | 否 | 2.5+ |
| ClickHouse | 否 | 否 | 部分 (PREWHERE) | 否 | 否 | -- |
| CockroachDB | 是 (vectorize=auto) | 部分 | 否 | 否 | 否 | 19.2+ |
| TiDB | 部分 (Plan Cache) | 否 | 部分 | 否 | 否 | 4.0+ |
| YugabyteDB | 否 | 否 | 否 | 否 | 否 | -- |
| OceanBase | 部分 (Plan Cache + SPM) | 否 | 部分 | 是 (SPM 反馈) | 否 | 4.0+ |
| Greenplum | 部分 (ORCA) | 否 | 是 (DPE) | 否 | 否 | 6.0+ |
| Vertica | 部分 | 是 (Adaptive Join) | 是 | 是 (Flex Query) | 否 | 8+ |
| Teradata | 部分 (Incremental Planning) | 否 | 是 (Partition Elimination) | 是 (Dynamic AMP Sampling) | 否 | V2R5+ |
| SAP HANA | 部分 | 否 | 是 | 是 (Plan Stability) | 否 | 2.0+ |
| Exasol | 否 | 否 | 否 | 是 (Auto Statistics) | 否 | -- |
| DuckDB | 否 | 否 | 否 (静态) | 否 | 否 | -- |
| Databricks | 是 (Photon AQE) | 是 | 是 | 是 | 是 | DBR 7.3+ |
| Flink SQL | 部分 (AQE 2.0+) | 部分 | 否 | 否 | 否 | 2.0 (2025) |
| Hive (on Tez) | 部分 (Dynamic Partition Pruning) | 否 | 是 | 否 | 否 | 2.0+ |
| Athena | 部分 | 部分 | 是 | 否 | 否 | 继承 Trino |
| StarRocks | 部分 (Runtime Filter) | 否 | 是 | 否 | 否 | 2.0+ |
| Doris | 部分 (Runtime Filter) | 否 | 是 | 否 | 否 | 1.0+ |
| ClickHouse | 否 | 否 | PREWHERE | 否 | 否 | -- |
| SingleStore (MemSQL) | 部分 | 部分 | 否 | 否 | 否 | 7.0+ |
| MonetDB | 否 | 否 | 否 | 否 | 否 | -- |
| CrateDB | 否 | 否 | 否 | 否 | 否 | -- |
| TimescaleDB | 否 (继承 PG) | 否 | Chunk Exclusion | 否 | 否 | -- |
| QuestDB | 否 | 否 | 否 | 否 | 否 | -- |
| Azure Synapse | 部分 | 是 (dedicated pool) | 是 | 否 | 否 | GA |
| Yellowbrick | 部分 | 部分 | 是 | 是 | 否 | GA |
| Firebolt | 部分 | 否 | 是 | 否 | 否 | GA |
| Materialize | 否 (增量视图) | N/A | N/A | N/A | N/A | -- |
| RisingWave | 否 (增量视图) | N/A | N/A | N/A | N/A | -- |
| Informix | 部分 | 否 | 否 | 是 | 否 | 11.10+ |
| Firebird | 否 | 否 | 否 | 否 | 否 | -- |
| H2 | 否 | 否 | 否 | 否 | 否 | -- |
| HSQLDB | 否 | 否 | 否 | 否 | 否 | -- |
| Derby | 否 | 否 | 否 | 否 | 否 | -- |
| Google Spanner | 否 | 否 | 否 | 否 | 否 | -- |

> 统计：45 个引擎中，约 18 个具备至少一种自适应能力；完整的"运行时计划切换 + 自适应 Join + 动态分区裁剪 + 统计反馈"组合仅 Oracle、Spark (AQE)、DB2 三家具备；BigQuery 虽具备但内部实现不公开。OLTP 引擎普遍不实现，OLAP 引擎普遍至少实现动态分区裁剪。

### 动态分区裁剪（DPP / Dynamic Filtering）支持

| 引擎 | 语法/机制 | 裁剪粒度 | 触发条件 | 版本 |
|------|---------|---------|---------|------|
| Oracle | 透明 | 分区 | Hash Join build 端 | 11g+ |
| SQL Server | Bitmap Filter | 页 | Hash Join build 端 | 2008+ |
| Spark (AQE) | `spark.sql.optimizer.dynamicPartitionPruning.enabled` | 分区 (Hive 分区) | Broadcast Join build 端 | 3.0+ |
| Databricks | 同 Spark，Photon 增强 | 分区 + 文件 + row group | 自动 | DBR 7.3+ |
| Trino | Dynamic Filtering | 分区 + split | Hash Join build 端 | 346+ |
| Impala | Runtime Filters (Bloom/MinMax) | 分区 + row group | Hash Join build 端 | 2.5+ |
| Hive (on Tez) | Dynamic Partition Pruning | 分区 | Broadcast Map Join | 2.0+ |
| StarRocks | Runtime Filter (Bloom/In/MinMax) | Tablet + row group | Hash Join build 端 | 2.0+ |
| Doris | Runtime Filter | Tablet + row group | Hash Join build 端 | 1.0+ |
| Greenplum | Dynamic Partition Elimination (DPE) | 分区 | Hash Join build 端 | 6.0+ |
| Vertica | Dynamic Projection Selection | Projection | Hash Join | 8+ |
| Teradata | Partition Elimination + Incremental Plan | 分区 | Dynamic AMP sampling | V14+ |
| BigQuery | Dynamic Pruning | 分区 + 文件 | 内部优化 | GA |
| Redshift | Zone Maps + Late Materialization | Block (1MB) | MergeJoin/HashJoin | 自动 |
| ClickHouse | PREWHERE（非严格 DPP） | Granule | WHERE 下推 | 持续 |
| TimescaleDB | Chunk Exclusion | Chunk (分区) | WHERE 谓词 | 1.0+ |
| DuckDB | Zonemaps + 过滤下推（静态） | Row group | 编译期决定 | 持续 |

### 自适应 Join 切换支持

| 引擎 | 切换模式 | 决策时机 | 默认算子 | 版本 |
|------|---------|---------|---------|------|
| Oracle | NL ↔ Hash | 执行中（subplan）| Optimizer Buffer | 12c (2013) |
| SQL Server | Hash ↔ Nested Loop | 执行前（先读 build 端） | Hash (Adaptive) | 2017 (批处理) / 2019 (行存) |
| Spark (AQE) | Sort-Merge ↔ Broadcast Hash | Stage 边界 | Sort-Merge | 3.0 (2020) |
| Databricks (Photon) | 同 Spark + Photon 内部 | Stage 边界 | Sort-Merge | DBR 7.3+ |
| DB2 (LEO) | 基于反馈重优化 | 下次编译 | 由 CBO 决定 | V8 (2004) |
| Vertica | Merge Join ↔ Hash Join | 执行前 | CBO 决定 | 8+ |
| SingleStore | NL ↔ Hash (部分) | 编译期 + 执行期 Hint | Hash | 7.0+ |
| Snowflake | 内部自适应（未公开细节） | 执行中 | 未公开 | GA |

### 自适应统计与重优化

| 引擎 | 机制 | 反馈方式 | 持久化 | 版本 |
|------|------|---------|--------|------|
| Oracle | Adaptive Statistics + Statistics Feedback | 执行后修正基数 | SQL Plan Directives | 12c (2013) |
| DB2 (LEO) | Learning Optimizer | 真实行数 vs 估计持久化 | Query Feedback Warehouse | V8 (2004) |
| Spark (AQE) | Stage 级重优化 | Shuffle 数据大小 | 单次查询内 | 3.0 (2020) |
| Databricks | Predictive Optimization + AQE | 历史查询模式 | 持久化 | DBR 10+ |
| Teradata | Dynamic AMP Sampling | 执行时真实数据分布 | 临时 | V2R5+ |
| OceanBase | SPM (SQL Plan Management) + Plan Baseline | 计划基线演化 | 持久化 | 4.0+ |
| Redshift | Adaptive Sort Spill + Predictive Query Execution | 内存压力反馈 | 持久化 (Autonomics) | 2019+ |
| Vertica | Flex Query Workload Analyzer | 执行反馈 | 物化 | 8+ |
| SAP HANA | Plan Stability + Adaptive Statistics | 执行后校正 | 持久化 | 2.0+ |
| BigQuery | 内部优化（未公开细节） | 未公开 | 未公开 | GA |
| Informix | Update Statistics Automation | 查询反馈 | 持久化 | 11.10+ |

## 逐引擎深度剖析

### Oracle Adaptive Plans（12c, 2013）

Oracle 在 **12.1（2013 年 7 月 GA）** 引入 "Adaptive Plans" 特性，是商业数据库首个完整的运行时自适应系统。

#### 核心组件

```
Adaptive Plans (自适应计划)
├── Adaptive Join Methods       -- NL ↔ Hash 动态切换
├── Adaptive Parallel Distribution -- PQ 分布方法动态切换
└── Performance Feedback        -- 并行度动态调整

Adaptive Statistics (自适应统计)
├── Dynamic Sampling            -- 编译期动态采样
├── Automatic Reoptimization    -- 执行后重编译
└── SQL Plan Directives         -- 跨查询持久化的修正提示
```

#### Adaptive Join 实现细节

```sql
-- 启用（12c 默认打开）
ALTER SESSION SET OPTIMIZER_ADAPTIVE_PLANS = TRUE;

-- 查询示例
SELECT /*+ DYNAMIC_SAMPLING(t1 4) */
    t1.id, t2.name
FROM orders t1 JOIN customers t2 ON t1.customer_id = t2.id
WHERE t1.order_date > SYSDATE - 7;

-- EXPLAIN PLAN 输出（节选）
-- NESTED LOOPS     (inactive)   <-- 原计划
-- HASH JOIN        (active)     <-- 运行时切换后
-- Note: - this is an adaptive plan
```

Oracle 的做法：

1. **双计划生成**：优化器同时编译 NL 和 Hash 两个子计划
2. **Inflection Point**：算一个阈值 T（通常几千行），如果 build 端真实行数 < T → 用 NL；否则切换到 Hash
3. **Statistics Collector**：在 build 端上方插入算子，缓冲行数直到达到 T 或读完
4. **零额外 I/O**：缓冲的行被复用到选中的 Join 算子，没有重复扫描

```
        +------------------+
        | Adaptive Join    |
        | (NL or Hash)     |
        +--------+---------+
                 |
        +--------+---------+
        | Stats Collector  |  <-- 关键算子：缓冲 build 端，触达 T 后决策
        +--------+---------+
                 |
        +--------+---------+
        | Build Scan       |
        +------------------+
```

#### Adaptive Statistics（12c, 默认关闭于 12.2+）

Oracle 12.1 默认开启 Adaptive Statistics，但由于产生大量 SQL Plan Directives 导致回归，**12.2（2017）默认关闭**，变为 `OPTIMIZER_ADAPTIVE_STATISTICS = FALSE`。

```sql
-- 检查当前设置
SELECT name, value FROM v$parameter
WHERE name LIKE 'optimizer_adaptive%';
-- optimizer_adaptive_plans      = TRUE   (12.1+ 默认)
-- optimizer_adaptive_statistics = FALSE  (12.2+ 默认)
-- optimizer_adaptive_reporting_only = FALSE

-- SQL Plan Directives（持久化的统计修正提示）
SELECT directive_id, state, auto_drop, type
FROM dba_sql_plan_directives
WHERE type = 'DYNAMIC_SAMPLING';
```

#### Automatic Reoptimization

第一次执行时，如果发现真实行数与估计严重偏离（通常 >2 倍），Oracle 在**游标关闭时**标记查询为"待重优化"。下次执行时用真实行数重新编译。

```sql
-- 检查是否发生重优化
SELECT sql_id, is_reoptimizable, executions
FROM v$sql WHERE sql_id = '...';
```

#### 版本演进

| 版本 | 年份 | 关键变化 |
|------|------|---------|
| 11g R2 | 2009 | Cardinality Feedback (原型，单次查询内) |
| 12.1.0.1 | 2013 | Adaptive Plans + Adaptive Statistics 默认开启 |
| 12.1.0.2 | 2014 | SQL Plan Directives 持久化 |
| 12.2 | 2017 | Adaptive Statistics 默认关闭（防止回归） |
| 18c | 2018 | Adaptive Plans 生效范围扩展 |
| 19c | 2019 | Automatic Indexing 引入（基于 workload 反馈） |
| 21c/23c | 2021/2023 | Real-Time Statistics（DML 即时统计更新） |

### SQL Server Adaptive Query Processing（2017 / 2019）

Microsoft 在 **SQL Server 2017** 随 CU1 引入 "Adaptive Query Processing"，包含三个子特性：

1. **Batch Mode Adaptive Joins**（2017，仅列存 + batch mode）
2. **Batch Mode Memory Grant Feedback**（2017）
3. **Interleaved Execution for MSTVFs**（2017）

SQL Server 2019 扩展到行存：

4. **Row Mode Adaptive Joins** (SQL Server 2019)
5. **Row Mode Memory Grant Feedback** (SQL Server 2019)
6. **Table Variable Deferred Compilation** (SQL Server 2019)

#### Adaptive Joins 实现

```sql
-- 前提: 兼容级别 140 (2017) 或 150 (2019)
ALTER DATABASE SomeDB SET COMPATIBILITY_LEVEL = 150;

-- 触发条件:
-- 1. 查询符合 Hash Join 形态
-- 2. build 端有列存或至少一个表支持 batch mode (2017)
-- 3. 2019 支持任意行存
```

SQL Server 的 adaptive join 与 Oracle 思路类似，但实现上：

- 在计划中是一个**"Adaptive Join"算子**（EXPLAIN 显式显示）
- 有一个 `Adaptive Threshold Rows` 属性（优化器算出的阈值）
- 读取 build 端时累计行数
- 行数 < threshold → Nested Loop (apply 形态)
- 行数 ≥ threshold → Hash Match

```sql
-- 查看 adaptive join
SELECT qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qp.query_plan.value('declare ...; count(...)', 'int') > 0;

-- 执行计划中会看到:
-- <AdaptiveJoin AdaptiveThresholdRows="4186" ... />
```

#### Memory Grant Feedback

执行后根据真实内存使用量修正下次的授予内存：

- 授予 2GB，实际只用 200MB → 下次授予 300MB
- 授予 2GB，spill 了 2GB → 下次授予 4GB
- 存储在 plan cache，连接断开丢失（2017）；2019 起引入"Persistent Mode"（但仍缓存在 plan 中）

### Spark Adaptive Query Execution (AQE)（3.0, 2020）

Spark AQE 是最广为人知的开源实现，**Spark 3.0（2020 年 6 月）** 正式 GA。

AQE 的本质：**利用 Shuffle 的物化边界作为重优化时机**。

#### 三大核心能力

1. **Dynamically coalescing shuffle partitions**（动态合并小分区）
2. **Dynamically switching join strategies**（动态切换 Join 策略：SMJ → Broadcast）
3. **Dynamically optimizing skew joins**（动态处理倾斜）

后续版本（3.2+）增加：

4. **Adaptive Local Shuffle Reader**
5. **Dynamic Partition Pruning (DPP)**（严格说 DPP 在 3.0 已有）
6. **Adaptive Repartition Removal**

```sql
-- 启用（3.2+ 默认开启）
SET spark.sql.adaptive.enabled = true;

-- 子特性
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.localShuffleReader.enabled = true;
SET spark.sql.adaptive.skewJoin.enabled = true;
SET spark.sql.optimizer.dynamicPartitionPruning.enabled = true;
```

#### AQE 工作原理

```
静态计划:
  Stage 1 (scan A) ──\
                      Shuffle ── Stage 3 (SMJ) ── Stage 4 (agg)
  Stage 2 (scan B) ──/

AQE 执行:
  1. Stage 1/2 完成 → 物化 shuffle 数据，统计真实大小
  2. AQE 触发：重新优化 "Stage 3" 及下游
     - 如果 A shuffle < broadcastThreshold → SMJ 改为 Broadcast Hash Join
     - 如果检测到倾斜 key → 拆分大分区为多个 tasks
     - 如果小分区过多 → 合并为一个 task
  3. 提交修正后的 Stage 3
```

**关键点**：AQE 只能在 Stage 边界（Shuffle / Broadcast Exchange）重优化，**无法在 Stage 内部切换算子**。这与 Oracle 的 "subplan 级切换" 有本质不同。

### Databricks Photon AQE

Databricks 在 DBR 7.3 引入 Photon 向量化引擎，并在 AQE 基础上增加：

- **Predictive I/O**：基于历史 workload 预测读取模式
- **Predictive Optimization**：自动 CLUSTER BY / OPTIMIZE
- **Enhanced DPP**：支持 Delta Lake 的文件级 + row group 级裁剪
- **Photon AQE**：AQE 决策与 Photon 向量化算子联动

### DB2 LEO（Learning Optimizer, V8, 2004）

IBM DB2 的 **Learning Optimizer (LEO)** 是商业数据库最早的自适应实现之一，**2004 年随 DB2 V8** 引入。

LEO 的核心思路：**监控执行期真实行数，持久化反馈到优化器**。

```
LEO 工作流程:
  Query Q 首次执行
    → 优化器基于静态统计估算 cardinality
    → 执行中每个算子计数真实行数
    → 对比估计 vs 真实: 偏差 > 阈值
    → 写入 SYSIBM.SYSADJUST_HISTORY
    → 下次 Q' 编译时，优化器查询历史反馈
    → 用修正后的 cardinality 重新规划
```

DB2 还有：

- **REOPT ONCE / REOPT ALWAYS**：强制绑定参数后重新编译
- **Real-Time Statistics** (DB2 9.5+)：DML 触发统计增量更新
- **Workload Manager + Query Patroller**：基于资源反馈的计划调整

```sql
-- DB2 启用 REOPT
BIND myapp.bnd REOPT ALWAYS;

-- 查看 LEO 反馈
SELECT * FROM SYSIBM.SYSADJUST_HISTORY
WHERE QUERYID = ... AND ADJUSTED_CARD <> ESTIMATED_CARD;
```

### Vertica Adaptive Join

Vertica 8.0 起引入 "Adaptive Join"，思路与 SQL Server 类似：

- 在 Hash Join 算子内部支持切换到 Merge Join
- 基于 build 端真实行数和内存压力
- 与 Vertica 的 Projection（物化视图）联动

Vertica 的特色是 **Flex Query Workload Analyzer**：执行后分析 workload，推荐 Projection 设计。

### CockroachDB 自适应向量化

CockroachDB **19.2（2019）** 引入 `vectorize=auto` 模式：

- 行存 + 小数据 → 使用传统 row-by-row 执行
- 大数据扫描 + 投影/聚合密集 → 切换到向量化执行
- **编译期基于估算行数**决定（不是真正的运行时切换）

```sql
SET vectorize = auto;     -- 默认
SET vectorize = on;       -- 强制向量化
SET vectorize = off;      -- 关闭
```

CockroachDB 不具备运行时计划切换能力，`vectorize=auto` 属于"自适应"但严格说是编译期决策。

### Trino Dynamic Filtering（346+, 2020）

Trino 在 **版本 346（2020 年 10 月）** 起增强 Dynamic Filtering，成为其自适应能力的核心：

```sql
-- 示例: 动态分区裁剪
SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE c.region = 'APAC';

-- Trino 执行流程:
-- 1. 扫描 customers，APAC 地区共 1000 customer_id
-- 2. build 端完成，收集 customer_id 集合
-- 3. 广播到所有 orders 扫描 worker
-- 4. orders 扫描时动态裁剪 partition / file / row group
```

关键配置：

```
dynamic-filtering.enabled = true
dynamic-filtering.wait-timeout = 1s
dynamic-filtering.small-broadcast.max-distinct-values-per-driver = 10000
```

Trino 不支持自适应 Join 策略切换，没有 AQE 风格的 stage 级重优化。

### Impala Runtime Filters（2.5+, 2016）

Impala 是第一个把 Runtime Filter（Bloom / MinMax）做到生产级的引擎之一，**Impala 2.5（2016 年 2 月）** 引入。

```sql
-- 自动启用
SET RUNTIME_FILTER_MODE = GLOBAL;  -- 默认

-- 查看 runtime filter
PROFILE;
-- 输出中有 "Filter X arrived", "Filter X rows rejected" 等指标
```

Impala 的 Runtime Filter 包含：

- **Bloom Filter**：大 build 端，高效但有假阳
- **MinMax Filter**：数值列，精确
- **In-list Filter**：小 build 端

### PostgreSQL：原生无自适应

PostgreSQL 核心优化器是纯静态 CBO，**无任何运行时自适应能力**。有两个间接方案：

#### 1. `pg_hint_plan` 循环式重优化

通过扩展 `pg_hint_plan` + 应用层逻辑模拟：

```sql
-- 步骤 1: 执行查询，EXPLAIN ANALYZE 拿到真实行数
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;

-- 步骤 2: 对比 estimated vs actual，如果偏差大
-- 步骤 3: 应用层生成 Hint，下次重新执行
/*+ HashJoin(orders customers) */ SELECT ...;
```

这不是真正的 AQP，是一种"外层 orchestration"。

#### 2. `aqo` 扩展（PostgreSQL Professional）

`aqo` (Adaptive Query Optimization) 是 PostgresPro 的扩展：

- 记录每条查询的真实行数
- 下次编译时用 ML（最近邻 / 线性回归）修正基数估计
- 仅修正 cardinality，不切换算子

```sql
CREATE EXTENSION aqo;
SET aqo.mode = 'learn';
-- 执行查询，aqo 记录反馈
SET aqo.mode = 'controlled';
-- 之后的查询自动使用学习到的基数
```

### Redshift Adaptive Sort / Spill

Amazon Redshift 具备若干自适应能力：

- **Adaptive Sort Spill** (2019+)：排序算子基于内存压力动态调整 spill 阈值
- **Concurrency Scaling**：workload 反馈自动扩缩并发集群
- **Predictive Query Execution**：基于历史查询模式调整资源分配
- **Autonomics**：自动 VACUUM / ANALYZE / encoding 选择

Redshift 没有 Oracle/SQL Server 式的 Adaptive Join 切换。

### OceanBase SQL Plan Management（SPM）

OceanBase 4.0 起的 SPM 属于"持久化反馈"式自适应：

- 为每条 SQL 保留多个 plan baseline
- 优化器选择 baseline 时参考历史执行反馈
- 支持 plan 演化（evolve）和固化（fix）

```sql
-- 查看 plan baseline
SELECT * FROM oceanbase.DBA_OB_SQL_PLAN_BASELINES;

-- 接受一个新 plan
CALL DBMS_SPM.ACCEPT_SQL_PLAN_BASELINE(...);
```

### BigQuery Dynamic Plans

BigQuery 基于 Dremel 架构，拥有内部 "Dynamic Plan" 机制：

- 查询树的 stage 在执行中可以重新分片
- 倾斜检测与重分区（类似 AQE skew join）
- 动态分区裁剪（Dynamic Pruning）对 TABLESAMPLE/分区表生效

Google 未公开具体实现细节，用户可见的是 INFORMATION_SCHEMA 中的 "stage" 变化。

### Greenplum ORCA + DPE

Greenplum 6.0 整合 ORCA 优化器，引入 **Dynamic Partition Elimination (DPE)**：

- Hash Join build 端完成后，动态裁剪 probe 端分区
- 仅对分区表生效
- 不支持 Join 策略切换

### Teradata Incremental Planning

Teradata 的自适应能力称为 **Incremental Planning / Dynamic AMP Sampling**：

- 编译期先用少量 AMP（节点）采样真实数据
- 动态调整 join 顺序和方法
- 执行中不切换算子

### Flink SQL AQE (2.0, 2025)

Apache Flink **2.0（2025）** 的批处理 SQL 引入 AQE 初步能力：

- 动态分区合并
- 倾斜处理（预览）
- Broadcast 切换（预览）

Flink AQE 受限于其流计算架构，远不如 Spark AQE 成熟。

### Materialize / RisingWave：增量视图无需 AQE

Materialize 和 RisingWave 是流式增量视图引擎，**计算模型与传统 SQL 完全不同**：

- 查询被编译为 dataflow 图，持续更新
- 没有"执行一次"的概念，因此无传统 AQE
- 数据倾斜处理通过 dataflow operator 设计解决

## Spark AQE 深度剖析

AQE 是开源领域文档最全、影响最广的 AQP 实现，值得详细解析。

### 1. Dynamic Shuffle Partition Coalescing

**问题**：Spark 默认 `spark.sql.shuffle.partitions = 200`，对小查询产生 200 个 tiny tasks，调度开销大。

**AQE 方案**：

```
未启用 AQE:
  200 partitions, 每个 5MB → 200 tasks, 调度开销占 80%

启用 AQE (spark.sql.adaptive.coalescePartitions.enabled=true):
  1. Shuffle 完成后，AQE 读取每个 partition 的真实大小
  2. 按 targetPostShuffleInputSize (默认 64MB) 合并相邻分区
  3. 200 partitions → 15 tasks
```

关键参数：

```
spark.sql.adaptive.coalescePartitions.enabled = true
spark.sql.adaptive.advisoryPartitionSizeInBytes = 64MB
spark.sql.adaptive.coalescePartitions.minPartitionNum = 1
spark.sql.adaptive.coalescePartitions.initialPartitionNum = 200
```

### 2. Dynamic Join Strategy Switching

**问题**：编译期估算 Table A = 10GB，选了 Sort-Merge Join。执行时 A 经过 filter 后只剩 5MB，但已经按 SMJ 规划好，错失 Broadcast 机会。

**AQE 方案**：

```
Stage 1: scan A 完成 → shuffle 数据真实大小 5MB
         < spark.sql.autoBroadcastJoinThreshold (默认 10MB)
         
AQE 决策:
  1. 原 SMJ 改为 Broadcast Hash Join
  2. 取消 Stage 1 的 Sort 操作
  3. 跳过 B 的 shuffle，直接 Broadcast A
  4. 提交新的 Stage 3 (Broadcast HJ)
```

限制：

- 仅 Sort-Merge → Broadcast，不支持反向（Broadcast 已经不需要 shuffle）
- 仅在 Stage 边界决策，Stage 内部已执行的算子不会撤销

### 3. Dynamic Skew Join Optimization

**问题**：Join key 倾斜，99% 的行集中在 1% 的 key 上，单个 reducer 处理绝大部分数据。

**AQE 方案**（SALT 变体）：

```
检测倾斜:
  partition_size > spark.sql.adaptive.skewJoin.skewedPartitionFactor (默认 5)
                   × median_partition_size
  AND
  partition_size > spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes
                   (默认 256MB)

处理倾斜:
  假设 A 有倾斜 partition P (5GB)，B 的对应 partition P' (100MB)
  
  1. 将 A 的 P 拆分为 N 个子 partition (P₁, P₂, ..., Pₙ)
  2. 将 B 的 P' 复制 N 份 (P'₁, P'₂, ..., P'ₙ)
  3. 每个 (Pᵢ, P'ᵢ) 作为独立 task 执行
  4. 结果正确（等价于原 Join）
  
拆分数量:
  N = ceil(partition_size / advisoryPartitionSizeInBytes)
```

参数：

```
spark.sql.adaptive.skewJoin.enabled = true
spark.sql.adaptive.skewJoin.skewedPartitionFactor = 5.0
spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes = 256MB
```

### 4. Dynamic Partition Pruning (DPP)

虽然是 Spark 3.0 AQE 之外独立开关，但通常一起启用：

```sql
-- 查询（星型模型）
SELECT f.* FROM fact f JOIN dim d ON f.dim_id = d.id
WHERE d.category = 'electronics';

-- 无 DPP: 扫描 fact 全部分区
-- DPP 启用:
--   1. 先扫描 dim，过滤 category = 'electronics'
--   2. 收集对应的 dim_id 集合
--   3. 广播到 fact 扫描 tasks
--   4. fact 根据 dim_id 动态裁剪分区
```

DPP 与 AQE 的关系：

- DPP 是编译期（planning）的自适应，在 physical plan 中插入 `DynamicPruningSubquery`
- AQE 是运行期（execution）的自适应，基于 shuffle 真实统计
- 两者独立启用，组合最佳

### 5. AQE 的限制

- **只能在 shuffle / broadcast 边界重优化**，Stage 内部算子固定
- **不支持 streaming**（结构化流不触发 AQE）
- **依赖 Shuffle 物化**，RDD API 不使用 AQE
- **Hint 会禁用 AQE**：如 `/*+ BROADCAST(a) */` 强制指定，AQE 不会覆盖
- **Cost 模型简化**：AQE 的决策主要基于 size，不考虑 CPU/IO 比例

## Oracle Adaptive Plans vs Adaptive Statistics

Oracle 的自适应能力分为两条线，常被混淆：

### Adaptive Plans（运行时，单次查询内）

- **作用域**：当前执行
- **触发**：执行中 Stats Collector 算子
- **修正**：Join 方法、PQ 分布
- **持久化**：否（下次查询重新决策）
- **控制参数**：`OPTIMIZER_ADAPTIVE_PLANS`（12.1+ 默认 TRUE）

### Adaptive Statistics（跨查询，持久化）

- **作用域**：后续查询
- **触发**：执行结束后对比估计 vs 真实
- **修正**：SQL Plan Directives（持久化统计修正提示）
- **持久化**：是，存储在 `DBA_SQL_PLAN_DIRECTIVES`
- **控制参数**：`OPTIMIZER_ADAPTIVE_STATISTICS`（12.2+ 默认 FALSE）

### 为什么 12.2 关闭 Adaptive Statistics

12.1 默认开启后，在生产环境出现三大问题：

1. **Directive 爆炸**：每个偏差的谓词组合生成一个 directive，几千条 SQL 产生几百万 directives
2. **编译时间增长**：查询优化时需要扫描 directives 表，复杂查询编译从毫秒级涨到秒级
3. **回归风险**：部分 directive 的修正反而导致计划变差

Oracle 的缓解方案：

- 12.2 默认关闭
- 引入 `DBMS_SPD.AUTO_DROP_SPD`（自动清理无用 directive）
- 21c Real-Time Statistics 替代部分 AS 功能

### 两者的关系示意

```
查询 Q1 首次执行:
  1. Optimizer 基于静态统计编译
  2. Adaptive Plans 在执行中可能切换 Join (NL→Hash)
  3. 执行结束后:
     - 如果 Adaptive Statistics 开启：对比 estimated vs actual
     - 偏差大 → 创建 SQL Plan Directive
  
查询 Q2（与 Q1 类似模式）编译:
  1. Optimizer 查询 directives
  2. 发现 Q1 的 directive 建议动态采样
  3. 编译期执行动态采样 → 得到更准的基数
  4. 生成更好的初始计划
  5. Adaptive Plans 在执行中继续做运行时修正
```

## 对引擎开发者的实现建议

### 1. Stats Collector 算子设计

```
StatsCollectorScan {
    child: Scan
    buffer: Vec<Row>
    threshold_rows: usize  // inflection point
    method_selected: Option<JoinMethod>
    
    fn next() -> Option<Row>:
        if method_selected.is_none():
            // 累积阶段
            row = child.next()?
            buffer.push(row)
            if buffer.len() >= threshold_rows:
                method_selected = Some(JoinMethod::Hash)
                // 后续直接切换
            return buffer.last_cloned()
        else:
            // 已决策
            child.next()
}
```

关键点：

- 缓冲区必须是**原地复用**，不能额外一次扫描
- 阈值由优化器通过成本模型计算
- 内存压力下可以提前"降级"（总是选 Hash，避免 OOM）

### 2. Shuffle 物化统计

AQE 的前提是 Shuffle 物化边界：

```
ShuffleWriter {
    partitions: Vec<PartitionWriter>
    stats: Vec<PartitionStats>  // 每个分区的大小、行数
    
    fn finish():
        // 写完 shuffle 文件后
        for i in 0..partitions.len():
            stats[i] = PartitionStats {
                bytes: partitions[i].bytes_written,
                rows: partitions[i].rows_written,
                skew_score: compute_skew(),
            }
        publish_stats()  // 发布给 Coordinator
}
```

### 3. Stage 级重优化触发器

```
AQECoordinator {
    fn on_stage_complete(stage: Stage, stats: StageStats):
        for downstream in stage.downstream_stages():
            let optimized = reoptimize(downstream, stats)
            if optimized.changed():
                submit_new_plan(downstream, optimized)
    
    fn reoptimize(stage, stats) -> Option<Stage>:
        // 1. Broadcast 判定
        if stats.size < broadcast_threshold:
            return Some(switch_to_broadcast(stage))
        
        // 2. Skew 判定
        if stats.has_skew():
            return Some(split_skewed_partitions(stage, stats))
        
        // 3. Coalesce 判定
        if stats.avg_partition_size < target_size:
            return Some(coalesce_partitions(stage, stats))
        
        None
}
```

### 4. Runtime Filter / Dynamic Filtering

```
Build side:
  HashBuild {
      bloom: BloomFilter,
      minmax: (Value, Value),
      in_list: Option<Vec<Value>>,
      
      fn add_row(row):
          bloom.insert(row.key)
          minmax.update(row.key)
          if in_list.is_some() && in_list.len() < MAX_IN_LIST:
              in_list.push(row.key)
          else:
              in_list = None  // 超出阈值，放弃精确集合
      
      fn finish() -> RuntimeFilter:
          publish_filter(self.bloom, self.minmax, self.in_list)
  }

Probe side:
  PartitionedScan {
      fn scan():
          wait_for_filter(timeout=1s)
          for partition in partitions:
              if !filter.might_match(partition.minmax):
                  skip_partition(partition)  // 关键：I/O 跳过
              else:
                  scan_partition(partition, filter)
  }
```

### 5. 持久化反馈（LEO 风格）

```
QueryFeedbackStore {
    // 按 (query_signature, operator_id) 索引
    feedback: HashMap<(QuerySig, OpId), FeedbackEntry>,
    
    fn record(query_sig, op_id, estimated, actual):
        entry = feedback.entry((query_sig, op_id))
        entry.samples.push((estimated, actual))
        if entry.samples.len() >= MIN_SAMPLES:
            entry.correction_factor = compute_ewma(entry.samples)
    
    fn query(query_sig, op_id) -> Option<CorrectionFactor>:
        feedback.get(&(query_sig, op_id))
            .map(|e| e.correction_factor)
}
```

### 6. 防止计划震荡

自适应系统的最大风险是"今天 A 计划明天 B 计划"，用户投诉性能不稳定。

缓解策略：

- **Plan Stability**：默认绑定 plan baseline，新 plan 需验证后才启用
- **Hysteresis**：切换阈值双向不同（防抖）
- **Performance Regression Detection**：监控新 plan 的实际执行时间，回退到旧计划
- **Hint Override**：允许用户强制禁用自适应

### 7. 内存压力下的降级

```
AdaptiveJoin {
    fn select_method(build_stats, memory_pressure) -> JoinMethod:
        if memory_pressure > HIGH_THRESHOLD:
            return JoinMethod::SortMerge  // 避免 hash table OOM
        
        if build_stats.rows < broadcast_threshold:
            return JoinMethod::Broadcast
        
        if build_stats.rows < NL_threshold:
            return JoinMethod::NestedLoop
        
        JoinMethod::Hash
}
```

## 关键发现与设计争议

### 发现 1：自适应不是免费午餐

- 运行时切换增加引擎复杂度 2-3 倍
- Plan 回归风险真实存在（Oracle 12.2 关闭 AS 就是教训）
- Stats Collector 有 5-10% 的 CPU 开销

### 发现 2：OLAP vs OLTP 的鸿沟

- OLAP 引擎（Spark/BigQuery/Databricks）普遍拥抱 AQE，因为查询时间长、shuffle 边界天然
- OLTP 引擎（MySQL/PostgreSQL/SQLite）基本不实现，因为单查询毫秒级、切换开销占比太高
- Oracle/SQL Server/DB2 作为 HTAP 两边都做，但 OLTP 路径的 adaptive 功能更保守

### 发现 3：Shuffle 物化是 AQE 的灵魂

Spark AQE 的成功依赖于 Shuffle Write 的物化边界，这是重优化的天然时机。对于纯 Pipeline 执行模型（如 Trino 流水线），AQE 很难实现，只能做 Dynamic Filtering。

### 发现 4：自适应 Join 的本质是"迟决策"

无论 Oracle / SQL Server / Spark，自适应 Join 都是把决策点从"编译期"推迟到"build 端完成后"。差异在于：

- Oracle / SQL Server：算子内部决策，零额外 I/O
- Spark AQE：Stage 边界决策，需要 Shuffle 物化

### 发现 5：动态分区裁剪的普适性

DPP / Runtime Filter 是最容易实现、收益最大的自适应能力，几乎所有 OLAP 引擎都支持。它的本质是"Build 端完成后向 Probe 端广播谓词"，不需要改变执行计划结构。

### 发现 6：PostgreSQL 的哲学分歧

PostgreSQL 社区长期抵制运行时自适应，理由：

- 增加核心复杂度
- 回归风险无法控制
- 用户可以通过 Hint / 手工 ANALYZE 解决

生态上由 `pg_hint_plan`、`aqo`、`pg_qualstats` 等扩展弥补，但始终不进入核心。

### 发现 7：Oracle SQL Plan Directives 的教训

12.1 激进默认开启 → 12.2 默认关闭，是数据库历史上少见的"功能降级"。教训：

- 自适应能力必须有强力的回归检测
- Directive 生命周期管理（自动清理）比生成更重要
- 默认行为应该保守

### 发现 8：商业引擎的黑箱困境

BigQuery、Snowflake、Redshift 的自适应能力信息极少公开：

- 用户看不到 EXPLAIN 中的 adaptive 决策
- 无法调参、无法禁用、无法诊断
- 对 SLA 敏感场景不友好

开源引擎（Spark/Trino/CockroachDB）在可观测性上有明显优势。

### 发现 9：流处理与增量视图不需要 AQE

Flink / Materialize / RisingWave 的计算模型是持续增量的，没有"一次性查询"，因此传统 AQE 不适用。这类系统通过 dataflow 图的静态优化 + 算子级别的负载均衡解决倾斜。

### 发现 10：自适应与 AI 优化的融合趋势

2023+ 年数据库界出现 ML 驱动的自适应优化：

- **Bao**（MIT）：强化学习选择 Hint
- **Neo**：神经网络预测基数
- **Balsa**：从真实执行时间学习计划
- Oracle 21c+：Automatic Indexing / Real-Time Statistics 基于历史 workload

未来趋势：传统规则驱动 AQE + ML 驱动预测 + 持久化反馈的融合。

## 总结对比矩阵

### 按能力维度总览

| 能力 | 最成熟 | 开源代表 | 商业代表 | 实施难度 |
|------|--------|---------|---------|---------|
| 运行时计划切换 | Oracle 12c | Spark AQE | Oracle | 高 |
| 自适应 Join | Oracle / SQL Server | Spark AQE | Oracle / SQL Server | 中 |
| 动态分区裁剪 | Spark / Impala | Spark / Trino / Impala | Oracle / BigQuery | 低 |
| 倾斜处理 | Spark AQE | Spark AQE | BigQuery | 中 |
| 统计反馈持久化 | DB2 LEO | AQO (PG 扩展) | Oracle SPD / DB2 LEO | 高 |
| Runtime Filter | Impala / StarRocks | Impala / Trino / StarRocks / Doris | SQL Server Bitmap | 低 |
| Memory Grant Feedback | SQL Server | -- | SQL Server | 中 |

### 按场景推荐

| 场景 | 推荐引擎 | 关键自适应能力 |
|------|---------|---------------|
| 大规模 Lakehouse ETL | Databricks / Spark | AQE + DPP + Photon |
| 传统企业 OLTP/HTAP | Oracle 19c+ | Adaptive Plans + SPM |
| 云数仓标准场景 | Snowflake / BigQuery | 内部自适应（黑箱） |
| 交互式 OLAP on 数据湖 | Trino 346+ | Dynamic Filtering |
| 高 QPS OLTP | MySQL / PostgreSQL + pg_hint_plan | 计划缓存 + 手工 Hint |
| 实时流 + 批混合 | Flink 2.0+ | 初步 AQE |
| 流式增量视图 | Materialize / RisingWave | 不需要 AQE |
| 单机分析 | DuckDB | 静态 CBO + 向量化 |

### 版本时间线

```
2004  DB2 V8 LEO
2008  SQL Server 2008 Bitmap Filter
2009  Oracle 11g R2 Cardinality Feedback (原型)
2013  Oracle 12c Adaptive Plans GA
2016  Impala 2.5 Runtime Filters
2017  SQL Server 2017 Adaptive Query Processing (batch mode)
2017  Oracle 12.2 Adaptive Statistics 默认关闭
2019  SQL Server 2019 Row Mode Adaptive Joins
2019  CockroachDB 19.2 vectorize=auto
2020  Spark 3.0 AQE GA
2020  Trino 346 Dynamic Filtering 增强
2021  Databricks Photon AQE
2023  Oracle 23c Real-Time Statistics
2025  Flink 2.0 批 AQE 预览
```

## 参考资料

- Oracle: [Adaptive Query Optimization](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/adaptive-query-optimization.html)
- Oracle: [SQL Plan Directives](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/optimizer-statistics-concepts.html)
- Microsoft: [Intelligent Query Processing](https://learn.microsoft.com/en-us/sql/relational-databases/performance/intelligent-query-processing)
- Microsoft: [Adaptive Joins](https://learn.microsoft.com/en-us/sql/relational-databases/performance/adaptive-joins)
- Apache Spark: [Adaptive Query Execution](https://spark.apache.org/docs/latest/sql-performance-tuning.html#adaptive-query-execution)
- Databricks: [How AQE Works in Spark 3.0](https://www.databricks.com/blog/2020/05/29/adaptive-query-execution-speeding-up-spark-sql-at-runtime.html)
- IBM DB2: [Learning Optimizer (LEO)](https://www.ibm.com/docs/en/db2-for-zos/13?topic=optimization-reoptimization)
- Trino: [Dynamic Filtering](https://trino.io/docs/current/admin/dynamic-filtering.html)
- Impala: [Runtime Filtering](https://impala.apache.org/docs/build/html/topics/impala_runtime_filtering.html)
- Vertica: [Adaptive Join](https://docs.vertica.com/latest/en/admin/analyzing-workloads/query-plan-metrics/)
- Greenplum: [Dynamic Partition Elimination](https://gpdb.docs.pivotal.io/6-0/admin_guide/query/topics/query-profiling.html)
- PostgresPro: [AQO Extension](https://github.com/postgrespro/aqo)
- Spark SQL: Yin Huai et al. "Adaptive Query Execution: Speeding Up Spark SQL at Runtime" (Databricks Engineering Blog, 2020)
- IBM LEO: Markl et al. "LEO - DB2's LEarning Optimizer" (VLDB 2001)
- Oracle Adaptive: Ziauddin et al. "Optimizer Plan Change Management: Improved Stability and Performance in Oracle 11g" (VLDB 2008)
- Bao: Marcus et al. "Bao: Making Learned Query Optimization Practical" (SIGMOD 2021)
