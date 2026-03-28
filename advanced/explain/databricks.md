# Databricks SQL: 执行计划与查询分析

> 参考资料:
> - [Databricks Documentation - EXPLAIN](https://docs.databricks.com/sql/language-manual/sql-ref-syntax-qry-explain.html)
> - [Databricks Documentation - Query Profile](https://docs.databricks.com/sql/user/queries/query-profile.html)


## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
```


## EXPLAIN 模式


简要模式（只显示物理计划）
```sql
EXPLAIN FORMATTED SELECT * FROM users WHERE age > 25;
```


扩展模式（逻辑计划 + 物理计划）
```sql
EXPLAIN EXTENDED SELECT * FROM users WHERE age > 25;
```


成本信息
```sql
EXPLAIN COST SELECT * FROM users WHERE age > 25;
```


代码生成
```sql
EXPLAIN CODEGEN SELECT * FROM users WHERE age > 25;
```


## Query Profile（Databricks SQL Warehouse）


在 Databricks SQL UI 中：
1. 执行查询
2. 点击 "Query Profile" 选项卡
3. 查看图形化执行计划

Query Profile 提供：
- 操作符 DAG
- 每个操作符的统计（行数、时间、数据量）
- Photon 加速标记
- 溢出信息

## 执行计划关键操作（Delta Lake）


PhotonScan           Photon 引擎扫描
FileScan parquet      文件扫描
Filter               过滤
Project              投影
BroadcastHashJoin    广播哈希连接
SortMergeJoin        排序合并连接
HashAggregate        哈希聚合
Exchange             数据交换
DeltaTableScan       Delta 表扫描（含数据跳过）

Photon 特有：
PhotonGroupingAgg    Photon 分组聚合
PhotonBroadcastHashJoin  Photon 广播连接
PhotonShuffledHashJoin   Photon Shuffle 连接

## Query History API


通过 SQL 查看查询历史
```sql
SELECT * FROM system.query.history
WHERE start_time > current_timestamp() - INTERVAL '1' HOUR
ORDER BY start_time DESC
LIMIT 10;
```


## 统计信息


收集统计信息
```sql
ANALYZE TABLE users COMPUTE STATISTICS;
ANALYZE TABLE users COMPUTE STATISTICS FOR COLUMNS username, age;
```


Delta Lake 自动收集统计信息
查看表详情
```sql
DESCRIBE DETAIL users;
DESCRIBE HISTORY users;
```


## Photon 引擎


Photon 是 Databricks 的原生向量化引擎
在 EXPLAIN 中标记 Photon 加速的操作符

## 自适应查询执行（AQE）


Databricks 默认启用 AQE
动态优化 Shuffle 分区、连接策略和数据倾斜

注意：Databricks SQL 基于 Spark SQL，EXPLAIN 语法类似
注意：Query Profile（Web UI）提供最直观的图形化执行计划
注意：Photon 引擎提供原生向量化加速
注意：Delta Lake 的数据跳过（Data Skipping）通过统计信息实现
注意：AQE 默认启用，运行时动态优化执行计划
注意：system.query.history 提供查询历史和性能数据
