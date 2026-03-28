# StarRocks: 执行计划与查询分析

> 参考资料:
> - [1] StarRocks Documentation - EXPLAIN / Query Profile
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. CBO 优化器: StarRocks 的核心竞争力

 StarRocks 的 CBO 优化器基于 Cascades 框架(Columbia 变体)，
 从 1.x 版本开始就是核心功能——比 Doris 的 Nereids(2.0)早约 2 年。

 CBO 关键能力:
   Join Reorder:        多表 JOIN 顺序优化(NP-hard，启发式搜索)
   子查询去关联:        将关联子查询改写为 JOIN
   聚合下推:            将聚合推到 Scan 侧(减少数据传输)
   分区裁剪:            基于 WHERE 条件跳过无关分区
   物化视图改写:        自动路由到 MV

 对比:
   Doris:      Nereids CBO(2.0+)，追赶中
   ClickHouse: RBO(规则优化)，无 CBO(设计选择)
   BigQuery:   CBO(Google Dremel 引擎)

## 2. EXPLAIN 级别

```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;
EXPLAIN COSTS SELECT * FROM users WHERE age > 25;

```

EXPLAIN ANALYZE: 实际执行并收集统计

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

```

## 3. Pipeline 执行引擎

 StarRocks 使用 Pipeline 执行引擎(vs Doris 的传统 Volcano 模型)。
 Pipeline 将执行计划拆分为多个 PipelineDriver，共享线程池。

 优势:
   减少线程上下文切换(Volcano 模型每个 Fragment 一个线程)
   更好的 CPU 利用率
   自适应并行度

 对比:
   Doris:     传统 Fragment + 线程模型(2.0 引入 Pipeline 实验性)
   ClickHouse: Pipeline 执行(类似概念)
   BigQuery:  Dremel 执行引擎(树形 Shuffle)

## 4. 统计信息

```sql
ANALYZE TABLE users;
ANALYZE TABLE users WITH SYNC;
ANALYZE TABLE users (username, age);
SHOW COLUMN STATS users;
SHOW TABLE STATS users;

```

## 5. Query Profile

```sql
SET enable_profile = true;

SHOW PROCESSLIST;
```

 FE Web UI: http://fe_host:8030

## 6. 执行计划关键算子

 OlapScanNode:       表扫描
 Exchange:           数据交换(BROADCAST/SHUFFLE/BUCKET_SHUFFLE)
 HashJoinNode:       哈希连接
 AggregateNode:      聚合
 SortNode:           排序
 AnalyticNode:       窗口函数
 ProjectNode:        投影

 StarRocks 特有:
   BUCKET_SHUFFLE:    利用分桶信息的本地 Shuffle(比全局 Shuffle 高效)
   COLOCATE_JOIN:     同组表本地 JOIN(零网络开销)

## 7. StarRocks vs Doris 执行计划差异

 CBO 优化器:
   StarRocks: Cascades CBO(1.x+，更成熟)
   Doris:     Nereids CBO(2.0+，追赶中)

 执行引擎:
   StarRocks: Pipeline 执行引擎(线程共享，高效)
   Doris:     传统 Fragment 模型(2.0 引入 Pipeline)

 Runtime Filter:
   StarRocks: Global Runtime Filter(跨 Fragment 广播 BF)
   Doris:     Local Runtime Filter(Fragment 内)

 对引擎开发者的参考:
   Cascades 框架的实现要点:
### 1. Memo(等价类存储): 存储所有等价的逻辑/物理计划

### 2. Rule(变换规则): 探索计划空间的搜索策略

### 3. Cost Model: 基于统计信息估算代价

StarRocks 的实现在 fe/optimizer/ 目录，值得深入研究。

