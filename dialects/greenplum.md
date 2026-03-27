# Greenplum

**分类**: MPP 数据库（基于 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4448 行

## 概述与定位

Greenplum 是基于 PostgreSQL 的大规模并行处理（MPP）分析数据库，由 Greenplum Inc. 于 2005 年推出，后被 EMC/Pivotal 收购，现为 VMware Tanzu 产品线的一部分，同时维护开源版本。Greenplum 通过将 PostgreSQL 实例作为 Segment 节点组成分布式集群，在保留完整 PostgreSQL SQL 能力的同时提供 PB 级数据分析能力。它在传统企业数仓、政府、电信等行业有大量部署。

## 历史与演进

- **2005 年**：Greenplum Database 1.0 发布，基于 PostgreSQL 8.2，引入 MPP 分布式执行框架。
- **2010 年**：被 EMC 收购，后整合到 Pivotal 产品线中。
- **2015 年**：Greenplum 开源（Apache 2.0 许可），社区版开始独立发展。
- **2017 年**：Greenplum 5.x 升级底层 PostgreSQL 内核到 8.3+，增强 ORCA 优化器。
- **2019 年**：Greenplum 6.x 基于 PostgreSQL 9.4 内核，引入 JSONB、并行化 VACUUM、Zstandard 压缩。
- **2022 年**：Greenplum 7.x 升级到 PostgreSQL 12 内核，支持 JIT 编译、分区表增强。
- **2024-2025 年**：持续推进云原生部署（Kubernetes）、存算分离架构和 Iceberg 集成。

## 核心设计思路

1. **基于 PostgreSQL 的 MPP**：每个 Segment 是一个完整的 PostgreSQL 实例，Master 节点负责 SQL 解析和计划分发，Segment 节点并行执行。
2. **DISTRIBUTED BY**：建表时必须指定分布键，数据按哈希分布到各 Segment，分布键选择直接影响 JOIN 性能和数据倾斜。
3. **ORCA 优化器**：自主研发的基于成本的查询优化器（Pivotal Query Optimizer），支持动态分区裁剪、子查询去关联等高级优化。
4. **外部表生态**：gpfdist（高速并行数据加载）、PXF（Platform Extension Framework）支持 HDFS、S3、Hive 等外部数据源的联邦查询。

## 独特特色

| 特性 | 说明 |
|---|---|
| **DISTRIBUTED BY** | 建表必须指定 `DISTRIBUTED BY (col)` 或 `DISTRIBUTED RANDOMLY`，控制数据在 Segment 间的分片策略。 |
| **gpfdist** | 高速并行数据加载服务器，将文件切分后从多个 Segment 同时读取，加载速度远超单点 COPY。 |
| **列式存储（AO 表）** | 支持 Append-Optimized 列存表，配合 Zlib/Zstandard/LZ4 压缩，适合大规模分析查询。 |
| **ORCA 优化器** | 独立于 PostgreSQL 原生优化器的高级优化器，对复杂多表 JOIN 和子查询有更好的执行计划选择。 |
| **资源队列/组** | 通过 Resource Queues 或 Resource Groups 实现多租户资源隔离，控制 CPU、内存和并发上限。 |
| **PXF 联邦查询** | 通过 PXF 连接器查询 HDFS/Hive/HBase/S3/JDBC 外部数据源，无需 ETL 导入。 |
| **MADlib 机器学习** | Apache MADlib 在 Greenplum 中提供并行化的机器学习算法（回归、分类、聚类等），在数据库内完成模型训练。 |

## 已知不足

- **PostgreSQL 版本滞后**：底层 PG 内核版本长期落后于社区版 PostgreSQL，新特性（如 MERGE、JSON_TABLE）引入较慢。
- **行级更新开销大**：AO 列存表不支持高效行级 UPDATE/DELETE，需要通过标记删除 + VACUUM 或 Heap 表替代。
- **分布键变更困难**：分布键一旦选定，变更需重建表并重新分布数据，对大表代价极高。
- **单点 Master**：Master 节点是单点，虽可配置 Standby Master，但高可用切换仍需人工干预或脚本。
- **社区活跃度下降**：被 VMware 收购后开源社区活跃度有所下降，与新一代云原生数仓竞品相比创新步伐放慢。

## 对引擎开发者的参考价值

- **PostgreSQL MPP 改造路径**：Greenplum 展示了如何在不大改 PostgreSQL 内核的前提下通过 Motion 节点实现分布式执行，对基于开源 RDBMS 构建 MPP 系统有直接参考。
- **ORCA 优化器架构**：独立进程的基于 Memo 的优化器设计（DXL 中间表示），对自研查询优化器有重要借鉴。
- **gpfdist 并行加载模型**：外部服务进程将文件切分并行推送到多个 Segment 的架构，对分布式批量数据导入有参考价值。
- **资源管理模型**：Resource Groups 基于 Linux cgroups 的 CPU/内存隔离实现，对数据库多租户资源管理有实践参考。
- **列存与行存混合**：在同一数据库中同时支持 Heap 行存表和 AO 列存表的设计，对混合负载引擎的存储层有启发。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [greenplum.sql](../ddl/create-table/greenplum.sql) |
| 改表 | [greenplum.sql](../ddl/alter-table/greenplum.sql) |
| 索引 | [greenplum.sql](../ddl/indexes/greenplum.sql) |
| 约束 | [greenplum.sql](../ddl/constraints/greenplum.sql) |
| 视图 | [greenplum.sql](../ddl/views/greenplum.sql) |
| 序列与自增 | [greenplum.sql](../ddl/sequences/greenplum.sql) |
| 数据库/Schema/用户 | [greenplum.sql](../ddl/users-databases/greenplum.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [greenplum.sql](../advanced/dynamic-sql/greenplum.sql) |
| 错误处理 | [greenplum.sql](../advanced/error-handling/greenplum.sql) |
| 执行计划 | [greenplum.sql](../advanced/explain/greenplum.sql) |
| 锁机制 | [greenplum.sql](../advanced/locking/greenplum.sql) |
| 分区 | [greenplum.sql](../advanced/partitioning/greenplum.sql) |
| 权限 | [greenplum.sql](../advanced/permissions/greenplum.sql) |
| 存储过程 | [greenplum.sql](../advanced/stored-procedures/greenplum.sql) |
| 临时表 | [greenplum.sql](../advanced/temp-tables/greenplum.sql) |
| 事务 | [greenplum.sql](../advanced/transactions/greenplum.sql) |
| 触发器 | [greenplum.sql](../advanced/triggers/greenplum.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [greenplum.sql](../dml/delete/greenplum.sql) |
| 插入 | [greenplum.sql](../dml/insert/greenplum.sql) |
| 更新 | [greenplum.sql](../dml/update/greenplum.sql) |
| Upsert | [greenplum.sql](../dml/upsert/greenplum.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [greenplum.sql](../functions/aggregate/greenplum.sql) |
| 条件函数 | [greenplum.sql](../functions/conditional/greenplum.sql) |
| 日期函数 | [greenplum.sql](../functions/date-functions/greenplum.sql) |
| 数学函数 | [greenplum.sql](../functions/math-functions/greenplum.sql) |
| 字符串函数 | [greenplum.sql](../functions/string-functions/greenplum.sql) |
| 类型转换 | [greenplum.sql](../functions/type-conversion/greenplum.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [greenplum.sql](../query/cte/greenplum.sql) |
| 全文搜索 | [greenplum.sql](../query/full-text-search/greenplum.sql) |
| 连接查询 | [greenplum.sql](../query/joins/greenplum.sql) |
| 分页 | [greenplum.sql](../query/pagination/greenplum.sql) |
| 行列转换 | [greenplum.sql](../query/pivot-unpivot/greenplum.sql) |
| 集合操作 | [greenplum.sql](../query/set-operations/greenplum.sql) |
| 子查询 | [greenplum.sql](../query/subquery/greenplum.sql) |
| 窗口函数 | [greenplum.sql](../query/window-functions/greenplum.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [greenplum.sql](../scenarios/date-series-fill/greenplum.sql) |
| 去重 | [greenplum.sql](../scenarios/deduplication/greenplum.sql) |
| 区间检测 | [greenplum.sql](../scenarios/gap-detection/greenplum.sql) |
| 层级查询 | [greenplum.sql](../scenarios/hierarchical-query/greenplum.sql) |
| JSON 展开 | [greenplum.sql](../scenarios/json-flatten/greenplum.sql) |
| 迁移速查 | [greenplum.sql](../scenarios/migration-cheatsheet/greenplum.sql) |
| TopN 查询 | [greenplum.sql](../scenarios/ranking-top-n/greenplum.sql) |
| 累计求和 | [greenplum.sql](../scenarios/running-total/greenplum.sql) |
| 缓慢变化维 | [greenplum.sql](../scenarios/slowly-changing-dim/greenplum.sql) |
| 字符串拆分 | [greenplum.sql](../scenarios/string-split-to-rows/greenplum.sql) |
| 窗口分析 | [greenplum.sql](../scenarios/window-analytics/greenplum.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [greenplum.sql](../types/array-map-struct/greenplum.sql) |
| 日期时间 | [greenplum.sql](../types/datetime/greenplum.sql) |
| JSON | [greenplum.sql](../types/json/greenplum.sql) |
| 数值类型 | [greenplum.sql](../types/numeric/greenplum.sql) |
| 字符串类型 | [greenplum.sql](../types/string/greenplum.sql) |
