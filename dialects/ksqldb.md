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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/ksqldb.sql) | STREAM/TABLE 二元模型(Kafka 主题绑定)，WITH 指定序列化 |
| [改表](../ddl/alter-table/ksqldb.sql) | 不支持 ALTER 修改 Schema，需重建 STREAM/TABLE |
| [索引](../ddl/indexes/ksqldb.sql) | 无索引（Kafka Streams 引擎），按 KEY 分区 |
| [约束](../ddl/constraints/ksqldb.sql) | 无约束支持，数据校验在 Producer 端 |
| [视图](../ddl/views/ksqldb.sql) | CSAS/CTAS 持续查询 = 物化视图（流式自动更新） |
| [序列与自增](../ddl/sequences/ksqldb.sql) | 无自增，KEY 来自 Kafka 消息 Key |
| [数据库/Schema/用户](../ddl/users-databases/ksqldb.sql) | 无 Schema 概念，STREAM/TABLE 扁平命名 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/ksqldb.sql) | 无动态 SQL，REST API/CLI 提交查询 |
| [错误处理](../advanced/error-handling/ksqldb.sql) | 无过程式错误处理，Dead Letter Queue 异常消息 |
| [执行计划](../advanced/explain/ksqldb.sql) | EXPLAIN 展示 Kafka Streams 拓扑 |
| [锁机制](../advanced/locking/ksqldb.sql) | 无锁（Kafka Streams 引擎），分区级并行 |
| [分区](../advanced/partitioning/ksqldb.sql) | Kafka 分区透传，PARTITION BY 重分区 |
| [权限](../advanced/permissions/ksqldb.sql) | ACL 集成 Kafka 权限，RBAC(Confluent Platform) |
| [存储过程](../advanced/stored-procedures/ksqldb.sql) | 无存储过程（流处理引擎） |
| [临时表](../advanced/temp-tables/ksqldb.sql) | 无临时表，所有查询结果持久化到 Kafka |
| [事务](../advanced/transactions/ksqldb.sql) | Exactly-Once 语义(Kafka 事务)，非传统 ACID |
| [触发器](../advanced/triggers/ksqldb.sql) | 无触发器，持续查询本身即事件驱动 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/ksqldb.sql) | TOMBSTONE(NULL 值) 标记删除，TABLE 语义 |
| [插入](../dml/insert/ksqldb.sql) | INSERT INTO 写入 STREAM/TABLE(Kafka 主题) |
| [更新](../dml/update/ksqldb.sql) | TABLE 语义按 KEY 更新最新值，非传统 UPDATE |
| [Upsert](../dml/upsert/ksqldb.sql) | TABLE 语义天然 Upsert(按 KEY 覆盖) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/ksqldb.sql) | COUNT/SUM/AVG+窗口聚合(TUMBLING/HOPPING/SESSION) |
| [条件函数](../functions/conditional/ksqldb.sql) | CASE/WHEN/IF 基础条件 |
| [日期函数](../functions/date-functions/ksqldb.sql) | TIMESTAMPADD/TIMESTAMPDIFF，FROM_UNIXTIME |
| [数学函数](../functions/math-functions/ksqldb.sql) | 基础数学函数 |
| [字符串函数](../functions/string-functions/ksqldb.sql) | CONCAT/SUBSTRING/TRIM 基础函数 |
| [类型转换](../functions/type-conversion/ksqldb.sql) | CAST 标准，Schema Registry 类型绑定 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/ksqldb.sql) | 不支持 CTE，用嵌套查询或多步 CSAS |
| [全文搜索](../query/full-text-search/ksqldb.sql) | 不支持全文搜索（流处理引擎） |
| [连接查询](../query/joins/ksqldb.sql) | STREAM-STREAM/STREAM-TABLE/TABLE-TABLE JOIN(流特有) |
| [分页](../query/pagination/ksqldb.sql) | 不支持分页（流处理无终态），LIMIT 仅 Pull 查询 |
| [行列转换](../query/pivot-unpivot/ksqldb.sql) | 不支持 PIVOT（流处理引擎） |
| [集合操作](../query/set-operations/ksqldb.sql) | 不支持 UNION/INTERSECT/EXCEPT |
| [子查询](../query/subquery/ksqldb.sql) | 不支持子查询，用多步 CSAS 替代 |
| [窗口函数](../query/window-functions/ksqldb.sql) | TUMBLING/HOPPING/SESSION 窗口(流处理独有)，无 OVER |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/ksqldb.sql) | 不适用（流处理场景） |
| [去重](../scenarios/deduplication/ksqldb.sql) | LATEST_BY_OFFSET 去重，TABLE 语义按 KEY 去重 |
| [区间检测](../scenarios/gap-detection/ksqldb.sql) | STREAM-STREAM JOIN WITHIN 时间窗口 |
| [层级查询](../scenarios/hierarchical-query/ksqldb.sql) | 不支持（流处理引擎） |
| [JSON 展开](../scenarios/json-flatten/ksqldb.sql) | EXTRACTJSONFIELD，结构化 Schema 自动映射 |
| [迁移速查](../scenarios/migration-cheatsheet/ksqldb.sql) | STREAM/TABLE 是核心概念，非传统 SQL，Kafka 原生 |
| [TopN 查询](../scenarios/ranking-top-n/ksqldb.sql) | TOPK/TOPKDISTINCT 聚合函数(独有) |
| [累计求和](../scenarios/running-total/ksqldb.sql) | 窗口聚合 SUM，无 OVER 子句 |
| [缓慢变化维](../scenarios/slowly-changing-dim/ksqldb.sql) | TABLE 语义天然维护最新值 |
| [字符串拆分](../scenarios/string-split-to-rows/ksqldb.sql) | 不支持原生拆分展开 |
| [窗口分析](../scenarios/window-analytics/ksqldb.sql) | TUMBLING/HOPPING/SESSION 窗口聚合，流式独有 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/ksqldb.sql) | ARRAY/MAP/STRUCT 类型，Schema Registry 定义 |
| [日期时间](../types/datetime/ksqldb.sql) | TIMESTAMP 毫秒精度，事件时间 ROWTIME |
| [JSON](../types/json/ksqldb.sql) | JSON 序列化格式，EXTRACTJSONFIELD 路径查询 |
| [数值类型](../types/numeric/ksqldb.sql) | INT/BIGINT/DOUBLE/DECIMAL 基础类型 |
| [字符串类型](../types/string/ksqldb.sql) | VARCHAR/STRING 标准，Schema Registry 管理 |
