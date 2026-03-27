# ksqlDB

**分类**: 流处理 SQL（Kafka）
**文件数**: 51 个 SQL 文件
**总行数**: 4208 行

## 概述与定位

ksqlDB 是 Confluent 公司开发的流处理 SQL 引擎，构建在 Apache Kafka Streams 之上。它让开发者可以用 SQL 语法对 Kafka 中持续流动的数据进行实时处理——无需编写 Java/Scala 代码。ksqlDB 定位于实时数据管道、事件驱动应用和流式 ETL 场景。其核心理念是将 Kafka Topic 抽象为 STREAM（不可变事件流）和 TABLE（可变状态表），用声明式 SQL 表达流处理逻辑。

## 历史与演进

- **2017 年**：Confluent 发布 KSQL 项目，首次将 SQL 引入 Kafka 流处理。
- **2019 年**：重命名为 ksqlDB，引入 Pull Query（点查询）能力和连接器集成。
- **2020 年**：增强物化视图和 REST API，向"事件流数据库"方向演进。
- **2021 年**：引入变量、ASSERT 语句和 Lambda 函数。
- **2022 年**：增强 JOIN 能力和性能优化。
- **2023-2025 年**：改进状态存储、增强容错能力，Confluent Cloud 全托管版持续演进。

## 核心设计思路

ksqlDB 的核心抽象是**STREAM 与 TABLE 的二元模型**。STREAM 表示不可变的事件序列（每条记录是一个追加事件），TABLE 表示可变的当前状态（相同 Key 的新记录覆盖旧记录）。所有数据存储在 Kafka Topic 中，ksqlDB 本身不管理持久化存储——它是 Kafka 之上的一个有状态流处理应用。查询分为 **Push Query**（`EMIT CHANGES`，持续推送结果）和 **Pull Query**（点查物化视图的当前状态）。

## 独特特色

- **STREAM vs TABLE**：`CREATE STREAM` 定义不可变事件流，`CREATE TABLE` 定义可变状态表——二者可相互转换。
- **EMIT CHANGES**：`SELECT * FROM stream EMIT CHANGES` 持续推送查询结果，实现实时监控。
- **Push/Pull 双模查询**：Push Query 订阅变更流，Pull Query 查询物化视图当前状态。
- **流式 JOIN**：支持 Stream-Stream、Stream-Table、Table-Table 多种 JOIN 模式，带时间窗口约束。
- **窗口聚合**：`WINDOW TUMBLING/HOPPING/SESSION` 支持滚动、跳跃和会话窗口。
- **连接器集成**：`CREATE SOURCE/SINK CONNECTOR` 直接管理 Kafka Connect 连接器。
- **Kafka 原生**：底层使用 Kafka Topic 存储数据，继承 Kafka 的持久性、分区和副本机制。

## 已知不足

- 不是通用关系型数据库——不支持 UPDATE/DELETE、事务、索引、外键等传统 SQL 特性。
- 查询能力有限：不支持子查询、CTE、复杂聚合和多层嵌套 JOIN。
- Pull Query 仅支持对物化视图的 Key 查找和简单过滤，不支持全表扫描。
- 状态存储（RocksDB）在大状态场景下可能成为性能瓶颈。
- 依赖 Kafka 集群，部署和运维复杂度包含 Kafka 本身。
- Schema 管理依赖 Confluent Schema Registry，增加了组件依赖。

## 对引擎开发者的参考价值

ksqlDB 展示了如何将 SQL 语义映射到流处理模型——STREAM/TABLE 二元抽象、Push/Pull 双模查询、以及流式 JOIN 的时间窗口语义是流 SQL 引擎设计的核心问题。其在 Kafka Streams 之上构建 SQL 层的方式展示了如何在已有流处理框架上叠加声明式查询能力。EMIT CHANGES 的持续查询模型也为理解流式物化视图提供了直观的参考。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [ksqldb.sql](../ddl/create-table/ksqldb.sql) |
| 改表 | [ksqldb.sql](../ddl/alter-table/ksqldb.sql) |
| 索引 | [ksqldb.sql](../ddl/indexes/ksqldb.sql) |
| 约束 | [ksqldb.sql](../ddl/constraints/ksqldb.sql) |
| 视图 | [ksqldb.sql](../ddl/views/ksqldb.sql) |
| 序列与自增 | [ksqldb.sql](../ddl/sequences/ksqldb.sql) |
| 数据库/Schema/用户 | [ksqldb.sql](../ddl/users-databases/ksqldb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [ksqldb.sql](../advanced/dynamic-sql/ksqldb.sql) |
| 错误处理 | [ksqldb.sql](../advanced/error-handling/ksqldb.sql) |
| 执行计划 | [ksqldb.sql](../advanced/explain/ksqldb.sql) |
| 锁机制 | [ksqldb.sql](../advanced/locking/ksqldb.sql) |
| 分区 | [ksqldb.sql](../advanced/partitioning/ksqldb.sql) |
| 权限 | [ksqldb.sql](../advanced/permissions/ksqldb.sql) |
| 存储过程 | [ksqldb.sql](../advanced/stored-procedures/ksqldb.sql) |
| 临时表 | [ksqldb.sql](../advanced/temp-tables/ksqldb.sql) |
| 事务 | [ksqldb.sql](../advanced/transactions/ksqldb.sql) |
| 触发器 | [ksqldb.sql](../advanced/triggers/ksqldb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [ksqldb.sql](../dml/delete/ksqldb.sql) |
| 插入 | [ksqldb.sql](../dml/insert/ksqldb.sql) |
| 更新 | [ksqldb.sql](../dml/update/ksqldb.sql) |
| Upsert | [ksqldb.sql](../dml/upsert/ksqldb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [ksqldb.sql](../functions/aggregate/ksqldb.sql) |
| 条件函数 | [ksqldb.sql](../functions/conditional/ksqldb.sql) |
| 日期函数 | [ksqldb.sql](../functions/date-functions/ksqldb.sql) |
| 数学函数 | [ksqldb.sql](../functions/math-functions/ksqldb.sql) |
| 字符串函数 | [ksqldb.sql](../functions/string-functions/ksqldb.sql) |
| 类型转换 | [ksqldb.sql](../functions/type-conversion/ksqldb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [ksqldb.sql](../query/cte/ksqldb.sql) |
| 全文搜索 | [ksqldb.sql](../query/full-text-search/ksqldb.sql) |
| 连接查询 | [ksqldb.sql](../query/joins/ksqldb.sql) |
| 分页 | [ksqldb.sql](../query/pagination/ksqldb.sql) |
| 行列转换 | [ksqldb.sql](../query/pivot-unpivot/ksqldb.sql) |
| 集合操作 | [ksqldb.sql](../query/set-operations/ksqldb.sql) |
| 子查询 | [ksqldb.sql](../query/subquery/ksqldb.sql) |
| 窗口函数 | [ksqldb.sql](../query/window-functions/ksqldb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [ksqldb.sql](../scenarios/date-series-fill/ksqldb.sql) |
| 去重 | [ksqldb.sql](../scenarios/deduplication/ksqldb.sql) |
| 区间检测 | [ksqldb.sql](../scenarios/gap-detection/ksqldb.sql) |
| 层级查询 | [ksqldb.sql](../scenarios/hierarchical-query/ksqldb.sql) |
| JSON 展开 | [ksqldb.sql](../scenarios/json-flatten/ksqldb.sql) |
| 迁移速查 | [ksqldb.sql](../scenarios/migration-cheatsheet/ksqldb.sql) |
| TopN 查询 | [ksqldb.sql](../scenarios/ranking-top-n/ksqldb.sql) |
| 累计求和 | [ksqldb.sql](../scenarios/running-total/ksqldb.sql) |
| 缓慢变化维 | [ksqldb.sql](../scenarios/slowly-changing-dim/ksqldb.sql) |
| 字符串拆分 | [ksqldb.sql](../scenarios/string-split-to-rows/ksqldb.sql) |
| 窗口分析 | [ksqldb.sql](../scenarios/window-analytics/ksqldb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [ksqldb.sql](../types/array-map-struct/ksqldb.sql) |
| 日期时间 | [ksqldb.sql](../types/datetime/ksqldb.sql) |
| JSON | [ksqldb.sql](../types/json/ksqldb.sql) |
| 数值类型 | [ksqldb.sql](../types/numeric/ksqldb.sql) |
| 字符串类型 | [ksqldb.sql](../types/string/ksqldb.sql) |
