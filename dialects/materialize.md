# Materialize

**分类**: 流式物化视图（兼容 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4756 行

## 概述与定位

Materialize 是一个流式物化视图数据库，兼容 PostgreSQL 协议。它的核心能力是让用户用标准 SQL 定义物化视图，然后系统自动对这些视图进行**增量维护**——当上游数据变更时，视图结果在毫秒级内更新，无需完整重算。Materialize 定位于需要低延迟实时分析的场景，如实时仪表盘、监控告警、实时特征工程和事件驱动业务逻辑。

## 历史与演进

- **2019 年**：Materialize 公司成立，核心团队来自 Timely Dataflow 和 Differential Dataflow 研究项目。
- **2020 年**：首个公开版本发布，展示增量物化视图能力。
- **2021 年**：引入 SOURCE 和 SINK 连接器，支持 Kafka、PostgreSQL CDC 等数据源。
- **2022 年**：推出 Materialize Cloud 托管服务，引入 SUBSCRIBE 持续查询。
- **2023 年**：增强多集群隔离、RBAC 权限管理和性能优化。
- **2024-2025 年**：持续增强 PG 兼容性、WebSocket 接口和企业级功能。

## 核心设计思路

Materialize 的底层引擎基于 **Timely Dataflow** 和 **Differential Dataflow** 两个 Rust 研究框架。核心理念是将 SQL 查询编译为数据流图（Dataflow Graph），其中每个操作符（Filter、Join、Aggregate 等）维护增量状态。当输入数据发生变更时，变更沿数据流图传播，每个操作符只处理变化的部分（差分计算），而非重算整个结果集。这使得复杂的多表 JOIN 和聚合也能在毫秒级完成增量更新。

## 独特特色

- **增量物化视图**：`CREATE MATERIALIZED VIEW` 定义的视图自动增量维护，数据变更后结果即时更新。
- **SOURCE/SINK**：`CREATE SOURCE FROM KAFKA ...` 和 `CREATE SINK ... INTO KAFKA ...` 连接外部数据流。
- **SUBSCRIBE**：`SUBSCRIBE TO view` 持续接收物化视图的变更事件（类似 CDC）。
- **PG 兼容**：使用 `psql` 或任意 PG 客户端连接，支持标准 SQL（JOIN、CTE、窗口函数等）。
- **Differential Dataflow**：底层差分数据流引擎支持任意复杂 SQL 的增量计算。
- **时间概念**：严格的事件时间处理，保证物化视图的一致性。
- **多集群隔离**：不同工作负载可部署在独立的计算集群中。

## 已知不足

- 不是通用 OLTP 数据库——不直接支持 INSERT/UPDATE/DELETE 到用户表（数据需从 SOURCE 导入）。
- 对于不断增长的无界数据集，某些物化视图的内存消耗可能不可控。
- 与 PostgreSQL 的兼容性有限：不支持存储过程、触发器、用户自定义类型等。
- 首次创建物化视图时需要全量计算一次快照，大数据集可能耗时较长。
- 生态系统和社区规模相比 PostgreSQL/MySQL 较小。
- 部分复杂窗口函数和高级 SQL 特性尚未完全支持。

## 对引擎开发者的参考价值

Materialize 是增量计算理论（Differential Dataflow）在数据库中的最完整实现，展示了如何将任意 SQL 查询转换为增量维护的数据流图。其差分数据流引擎的设计——在有向无环图中传播"变更集合"（differences）而非完整数据——是流式计算和物化视图领域的前沿研究成果。SOURCE/SINK 的抽象设计也为理解数据库与流处理系统的边界提供了参考。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/materialize.sql) | 流式物化视图引擎，SOURCE 定义数据源(Kafka/PG CDC) |
| [改表](../ddl/alter-table/materialize.sql) | ALTER 能力有限，SOURCE/SINK 属性修改 |
| [索引](../ddl/indexes/materialize.sql) | INDEX 加速查询(内存中维护)，非传统 B-tree |
| [约束](../ddl/constraints/materialize.sql) | 无约束支持（流处理定位） |
| [视图](../ddl/views/materialize.sql) | MATERIALIZED VIEW 核心功能，增量维护（Differential Dataflow） |
| [序列与自增](../ddl/sequences/materialize.sql) | 无 SEQUENCE/自增（流处理定位） |
| [数据库/Schema/用户](../ddl/users-databases/materialize.sql) | Cluster/Database/Schema 命名空间，RBAC |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/materialize.sql) | 无动态 SQL（查询引擎定位） |
| [错误处理](../advanced/error-handling/materialize.sql) | 无过程式错误处理 |
| [执行计划](../advanced/explain/materialize.sql) | EXPLAIN 展示 Differential Dataflow 数据流计划 |
| [锁机制](../advanced/locking/materialize.sql) | 无锁（流式物化视图引擎），MVCC 快照读 |
| [分区](../advanced/partitioning/materialize.sql) | 无传统分区，数据流分片自动管理 |
| [权限](../advanced/permissions/materialize.sql) | RBAC 权限模型(PG 兼容语法) |
| [存储过程](../advanced/stored-procedures/materialize.sql) | 无存储过程（流式引擎定位） |
| [临时表](../advanced/temp-tables/materialize.sql) | TEMPORARY VIEW 支持 |
| [事务](../advanced/transactions/materialize.sql) | Strict Serializable 一致性(最强)，实时物化视图 |
| [触发器](../advanced/triggers/materialize.sql) | 无触发器，物化视图即增量触发 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/materialize.sql) | DELETE 支持(TABLE 类型)，SOURCE 数据不可删除 |
| [插入](../dml/insert/materialize.sql) | INSERT INTO TABLE 支持，SOURCE 由外部推送 |
| [更新](../dml/update/materialize.sql) | UPDATE 支持(TABLE 类型) |
| [Upsert](../dml/upsert/materialize.sql) | Upsert Source(Kafka Key 语义)，ENVELOPE UPSERT |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/materialize.sql) | PG 兼容聚合，增量维护聚合结果 |
| [条件函数](../functions/conditional/materialize.sql) | CASE/COALESCE/NULLIF(PG 兼容) |
| [日期函数](../functions/date-functions/materialize.sql) | PG 兼容日期函数，mz_now() 逻辑时间 |
| [数学函数](../functions/math-functions/materialize.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/materialize.sql) | PG 兼容字符串函数，|| 拼接 |
| [类型转换](../functions/type-conversion/materialize.sql) | CAST/:: 运算符(PG 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/materialize.sql) | WITH 标准支持(PG 兼容) |
| [全文搜索](../query/full-text-search/materialize.sql) | 无全文搜索 |
| [连接查询](../query/joins/materialize.sql) | JOIN 自动增量维护(Differential Dataflow 核心优势) |
| [分页](../query/pagination/materialize.sql) | LIMIT/OFFSET(PG 兼容)，物化视图毫秒级响应 |
| [行列转换](../query/pivot-unpivot/materialize.sql) | 无原生 PIVOT(PG 兼容) |
| [集合操作](../query/set-operations/materialize.sql) | UNION ALL/EXCEPT ALL(增量维护) |
| [子查询](../query/subquery/materialize.sql) | 关联子查询(PG 兼容)，增量维护 |
| [窗口函数](../query/window-functions/materialize.sql) | 窗口函数支持(PG 兼容)，增量维护 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/materialize.sql) | generate_series(PG 兼容) |
| [去重](../scenarios/deduplication/materialize.sql) | DISTINCT ON/ROW_NUMBER(PG 兼容)，增量去重 |
| [区间检测](../scenarios/gap-detection/materialize.sql) | 窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/materialize.sql) | 递归 CTE(有限支持)，增量维护 |
| [JSON 展开](../scenarios/json-flatten/materialize.sql) | jsonb_each/jsonb_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/materialize.sql) | PG 兼容 SQL+流式物化视图是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/materialize.sql) | ROW_NUMBER+LIMIT(PG 兼容)，物化视图实时排名 |
| [累计求和](../scenarios/running-total/materialize.sql) | SUM() OVER(PG 兼容)，增量计算 |
| [缓慢变化维](../scenarios/slowly-changing-dim/materialize.sql) | Temporal Filter+物化视图增量维护 |
| [字符串拆分](../scenarios/string-split-to-rows/materialize.sql) | regexp_split_to_table(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/materialize.sql) | 窗口函数(PG 兼容)，增量维护是核心优势 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/materialize.sql) | LIST/MAP/RECORD 类型(PG 兼容扩展) |
| [日期时间](../types/datetime/materialize.sql) | TIMESTAMP/DATE/TIME/INTERVAL(PG 兼容)，mz_now() |
| [JSON](../types/json/materialize.sql) | JSONB(PG 兼容)，jsonb_each/array_elements 展开 |
| [数值类型](../types/numeric/materialize.sql) | INT/BIGINT/FLOAT/DOUBLE/NUMERIC(PG 兼容) |
| [字符串类型](../types/string/materialize.sql) | TEXT/VARCHAR(PG 兼容)，UTF-8 |
