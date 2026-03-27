# YugabyteDB

**分类**: 分布式数据库（兼容 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4726 行

## 概述与定位

YugabyteDB 是 Yugabyte 公司于 2017 年开源的分布式 SQL 数据库，核心设计目标是提供与 PostgreSQL 完全兼容的分布式数据库体验。它采用 Google Spanner 的分布式架构理念，同时复用 PostgreSQL 的查询层代码实现高度 PG 兼容。YugabyteDB 定位于需要水平扩展、高可用和全球分布的 OLTP 应用，特别适合从单机 PostgreSQL 向分布式架构迁移的场景。

## 历史与演进

- **2016 年**：前 Facebook 和 Oracle 工程师创立 Yugabyte 公司。
- **2017 年**：YugabyteDB 开源，初期仅提供 Cassandra 兼容的 YCQL API。
- **2018 年**：引入 YSQL API，直接集成 PostgreSQL 查询层实现 SQL 兼容。
- **2019 年**：2.0 GA，YSQL 基于 PG 11 fork 实现全面 SQL 支持。
- **2021 年**：2.8+ 引入跨地域部署增强和读副本（Read Replica）。
- **2022 年**：升级到 PG 11.2 兼容层，增强 xCluster 异步复制。
- **2023-2024 年**：基于 PG 15 的查询层升级，增强连接管理和性能优化。
- **2025 年**：持续推进 PG 兼容性和 YugabyteDB Anywhere/Managed 云服务。

## 核心设计思路

YugabyteDB 采用两层架构：**YB-TServer**（Tablet Server）管理数据存储，**YB-Master** 管理元数据和集群协调。数据按表分成多个 **Tablet**（类似 Spanner 的 Split），每个 Tablet 通过 Raft 共识协议维护多副本。存储层使用 DocDB（基于 RocksDB 改造的文档存储引擎），支持 MVCC 和分布式事务。独特之处在于提供**双 API**：YSQL（兼容 PostgreSQL）和 YCQL（兼容 Cassandra Query Language），共享同一底层存储引擎。

## 独特特色

- **YSQL/YCQL 双 API**：同一集群通过不同端口同时提供 PostgreSQL 兼容和 Cassandra 兼容接口。
- **哈希分片 + Range 分片**：默认使用哈希分片均匀分布数据，也支持 Range 分片用于范围查询优化。
- **Tablet 分裂与合并**：数据增长时 Tablet 自动分裂，支持手动和自动触发。
- **高度 PG 兼容**：直接复用 PostgreSQL 查询层代码，支持 PG 扩展、存储过程、触发器。
- **Colocated Tables**：`CREATE DATABASE ... WITH COLOCATED = true` 将小表共置于单一 Tablet 减少开销。
- **xCluster 复制**：跨集群异步复制用于异地灾备和读扩展。
- **地理分区**：`TABLESPACE` 机制控制数据的地域放置。

## 已知不足

- 哈希分片默认策略下范围查询（如 `BETWEEN`、`ORDER BY` 主键）性能不如 Range 分片。
- 与 PostgreSQL 的兼容虽高但并非 100%，部分扩展和高级特性可能不支持。
- YCQL API 功能更新速度慢于 YSQL，部分用户反馈 YCQL 的定位逐渐模糊。
- 分布式事务在高冲突场景下延迟高于单机 PostgreSQL。
- 集群最小部署需要 3 节点，对小规模应用有一定门槛。
- 全局二级索引在分布式场景下的性能开销需要关注。

## 对引擎开发者的参考价值

YugabyteDB 展示了如何通过 fork PostgreSQL 查询层快速获得 SQL 兼容性，同时将存储引擎替换为分布式方案的工程策略。其双 API 设计（SQL + NoSQL 共享存储）是多模数据库架构的有益探索。Tablet 的哈希 vs Range 分片选择、Colocated Tables 的小表优化策略、以及 DocDB 存储引擎的设计对分布式存储开发者有直接参考意义。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [yugabytedb.sql](../ddl/create-table/yugabytedb.sql) |
| 改表 | [yugabytedb.sql](../ddl/alter-table/yugabytedb.sql) |
| 索引 | [yugabytedb.sql](../ddl/indexes/yugabytedb.sql) |
| 约束 | [yugabytedb.sql](../ddl/constraints/yugabytedb.sql) |
| 视图 | [yugabytedb.sql](../ddl/views/yugabytedb.sql) |
| 序列与自增 | [yugabytedb.sql](../ddl/sequences/yugabytedb.sql) |
| 数据库/Schema/用户 | [yugabytedb.sql](../ddl/users-databases/yugabytedb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [yugabytedb.sql](../advanced/dynamic-sql/yugabytedb.sql) |
| 错误处理 | [yugabytedb.sql](../advanced/error-handling/yugabytedb.sql) |
| 执行计划 | [yugabytedb.sql](../advanced/explain/yugabytedb.sql) |
| 锁机制 | [yugabytedb.sql](../advanced/locking/yugabytedb.sql) |
| 分区 | [yugabytedb.sql](../advanced/partitioning/yugabytedb.sql) |
| 权限 | [yugabytedb.sql](../advanced/permissions/yugabytedb.sql) |
| 存储过程 | [yugabytedb.sql](../advanced/stored-procedures/yugabytedb.sql) |
| 临时表 | [yugabytedb.sql](../advanced/temp-tables/yugabytedb.sql) |
| 事务 | [yugabytedb.sql](../advanced/transactions/yugabytedb.sql) |
| 触发器 | [yugabytedb.sql](../advanced/triggers/yugabytedb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [yugabytedb.sql](../dml/delete/yugabytedb.sql) |
| 插入 | [yugabytedb.sql](../dml/insert/yugabytedb.sql) |
| 更新 | [yugabytedb.sql](../dml/update/yugabytedb.sql) |
| Upsert | [yugabytedb.sql](../dml/upsert/yugabytedb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [yugabytedb.sql](../functions/aggregate/yugabytedb.sql) |
| 条件函数 | [yugabytedb.sql](../functions/conditional/yugabytedb.sql) |
| 日期函数 | [yugabytedb.sql](../functions/date-functions/yugabytedb.sql) |
| 数学函数 | [yugabytedb.sql](../functions/math-functions/yugabytedb.sql) |
| 字符串函数 | [yugabytedb.sql](../functions/string-functions/yugabytedb.sql) |
| 类型转换 | [yugabytedb.sql](../functions/type-conversion/yugabytedb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [yugabytedb.sql](../query/cte/yugabytedb.sql) |
| 全文搜索 | [yugabytedb.sql](../query/full-text-search/yugabytedb.sql) |
| 连接查询 | [yugabytedb.sql](../query/joins/yugabytedb.sql) |
| 分页 | [yugabytedb.sql](../query/pagination/yugabytedb.sql) |
| 行列转换 | [yugabytedb.sql](../query/pivot-unpivot/yugabytedb.sql) |
| 集合操作 | [yugabytedb.sql](../query/set-operations/yugabytedb.sql) |
| 子查询 | [yugabytedb.sql](../query/subquery/yugabytedb.sql) |
| 窗口函数 | [yugabytedb.sql](../query/window-functions/yugabytedb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [yugabytedb.sql](../scenarios/date-series-fill/yugabytedb.sql) |
| 去重 | [yugabytedb.sql](../scenarios/deduplication/yugabytedb.sql) |
| 区间检测 | [yugabytedb.sql](../scenarios/gap-detection/yugabytedb.sql) |
| 层级查询 | [yugabytedb.sql](../scenarios/hierarchical-query/yugabytedb.sql) |
| JSON 展开 | [yugabytedb.sql](../scenarios/json-flatten/yugabytedb.sql) |
| 迁移速查 | [yugabytedb.sql](../scenarios/migration-cheatsheet/yugabytedb.sql) |
| TopN 查询 | [yugabytedb.sql](../scenarios/ranking-top-n/yugabytedb.sql) |
| 累计求和 | [yugabytedb.sql](../scenarios/running-total/yugabytedb.sql) |
| 缓慢变化维 | [yugabytedb.sql](../scenarios/slowly-changing-dim/yugabytedb.sql) |
| 字符串拆分 | [yugabytedb.sql](../scenarios/string-split-to-rows/yugabytedb.sql) |
| 窗口分析 | [yugabytedb.sql](../scenarios/window-analytics/yugabytedb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [yugabytedb.sql](../types/array-map-struct/yugabytedb.sql) |
| 日期时间 | [yugabytedb.sql](../types/datetime/yugabytedb.sql) |
| JSON | [yugabytedb.sql](../types/json/yugabytedb.sql) |
| 数值类型 | [yugabytedb.sql](../types/numeric/yugabytedb.sql) |
| 字符串类型 | [yugabytedb.sql](../types/string/yugabytedb.sql) |
