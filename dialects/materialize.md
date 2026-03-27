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

| 模块 | 链接 |
|---|---|
| 建表 | [materialize.sql](../ddl/create-table/materialize.sql) |
| 改表 | [materialize.sql](../ddl/alter-table/materialize.sql) |
| 索引 | [materialize.sql](../ddl/indexes/materialize.sql) |
| 约束 | [materialize.sql](../ddl/constraints/materialize.sql) |
| 视图 | [materialize.sql](../ddl/views/materialize.sql) |
| 序列与自增 | [materialize.sql](../ddl/sequences/materialize.sql) |
| 数据库/Schema/用户 | [materialize.sql](../ddl/users-databases/materialize.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [materialize.sql](../advanced/dynamic-sql/materialize.sql) |
| 错误处理 | [materialize.sql](../advanced/error-handling/materialize.sql) |
| 执行计划 | [materialize.sql](../advanced/explain/materialize.sql) |
| 锁机制 | [materialize.sql](../advanced/locking/materialize.sql) |
| 分区 | [materialize.sql](../advanced/partitioning/materialize.sql) |
| 权限 | [materialize.sql](../advanced/permissions/materialize.sql) |
| 存储过程 | [materialize.sql](../advanced/stored-procedures/materialize.sql) |
| 临时表 | [materialize.sql](../advanced/temp-tables/materialize.sql) |
| 事务 | [materialize.sql](../advanced/transactions/materialize.sql) |
| 触发器 | [materialize.sql](../advanced/triggers/materialize.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [materialize.sql](../dml/delete/materialize.sql) |
| 插入 | [materialize.sql](../dml/insert/materialize.sql) |
| 更新 | [materialize.sql](../dml/update/materialize.sql) |
| Upsert | [materialize.sql](../dml/upsert/materialize.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [materialize.sql](../functions/aggregate/materialize.sql) |
| 条件函数 | [materialize.sql](../functions/conditional/materialize.sql) |
| 日期函数 | [materialize.sql](../functions/date-functions/materialize.sql) |
| 数学函数 | [materialize.sql](../functions/math-functions/materialize.sql) |
| 字符串函数 | [materialize.sql](../functions/string-functions/materialize.sql) |
| 类型转换 | [materialize.sql](../functions/type-conversion/materialize.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [materialize.sql](../query/cte/materialize.sql) |
| 全文搜索 | [materialize.sql](../query/full-text-search/materialize.sql) |
| 连接查询 | [materialize.sql](../query/joins/materialize.sql) |
| 分页 | [materialize.sql](../query/pagination/materialize.sql) |
| 行列转换 | [materialize.sql](../query/pivot-unpivot/materialize.sql) |
| 集合操作 | [materialize.sql](../query/set-operations/materialize.sql) |
| 子查询 | [materialize.sql](../query/subquery/materialize.sql) |
| 窗口函数 | [materialize.sql](../query/window-functions/materialize.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [materialize.sql](../scenarios/date-series-fill/materialize.sql) |
| 去重 | [materialize.sql](../scenarios/deduplication/materialize.sql) |
| 区间检测 | [materialize.sql](../scenarios/gap-detection/materialize.sql) |
| 层级查询 | [materialize.sql](../scenarios/hierarchical-query/materialize.sql) |
| JSON 展开 | [materialize.sql](../scenarios/json-flatten/materialize.sql) |
| 迁移速查 | [materialize.sql](../scenarios/migration-cheatsheet/materialize.sql) |
| TopN 查询 | [materialize.sql](../scenarios/ranking-top-n/materialize.sql) |
| 累计求和 | [materialize.sql](../scenarios/running-total/materialize.sql) |
| 缓慢变化维 | [materialize.sql](../scenarios/slowly-changing-dim/materialize.sql) |
| 字符串拆分 | [materialize.sql](../scenarios/string-split-to-rows/materialize.sql) |
| 窗口分析 | [materialize.sql](../scenarios/window-analytics/materialize.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [materialize.sql](../types/array-map-struct/materialize.sql) |
| 日期时间 | [materialize.sql](../types/datetime/materialize.sql) |
| JSON | [materialize.sql](../types/json/materialize.sql) |
| 数值类型 | [materialize.sql](../types/numeric/materialize.sql) |
| 字符串类型 | [materialize.sql](../types/string/materialize.sql) |
