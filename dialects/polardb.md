# PolarDB

**分类**: 云原生数据库（阿里云，兼容 MySQL）
**文件数**: 51 个 SQL 文件
**总行数**: 3925 行

## 概述与定位

PolarDB 是阿里云自主研发的云原生关系型数据库，采用计算与存储分离的共享存储架构。PolarDB 提供 MySQL 版、PostgreSQL 版和分布式版（PolarDB-X）三个产品形态，覆盖从兼容性迁移到分布式扩展的完整场景。其核心优势在于：在保持与 MySQL/PG 高度兼容的同时，利用云原生存储实现快速弹性扩展、秒级只读副本扩容和按用量计费。

## 历史与演进

- **2017 年**：PolarDB MySQL 版首次公开预览，采用共享存储架构。
- **2018 年**：PolarDB MySQL 版 GA，支持最大 100TB 存储和 16 个只读节点。
- **2019 年**：推出 PolarDB PostgreSQL 版（基于 PG 11）。
- **2020 年**：PolarDB-X（分布式版）GA，支持水平拆分和分布式事务。
- **2021 年**：开源 PolarDB for PostgreSQL，引入 HTAP 能力（列存索引）。
- **2022 年**：Serverless 弹性版发布，实现按需自动扩缩容。
- **2023-2025 年**：增强全局索引、多主架构探索、向量检索和 AI 集成。

## 核心设计思路

PolarDB 的核心创新是**共享存储架构**：一个读写主节点和多个只读节点共享同一份分布式存储（PolarStore/PolarFS）。只读节点通过物理复制（Redo Log Shipping）保持与主节点的数据一致，延迟通常在毫秒级。这种架构避免了传统主从复制的数据冗余，只读副本可秒级创建且不占额外存储空间。存储层使用 RDMA 网络和 NVMe SSD 实现接近本地存储的 IO 性能。

## 独特特色

- **共享存储零冗余**：只读节点不复制数据，共享同一存储卷，存储成本仅为传统方案的 1/N。
- **秒级只读扩展**：新增只读节点无需数据拷贝，秒级可用。
- **全局索引**（分布式版）：在分布式场景下提供跨分片的全局唯一索引。
- **并行查询**：单条 SQL 可利用多核并行执行，加速 OLAP 类查询。
- **列存索引 (IMCI)**：In-Memory Column Index 提供实时分析能力。
- **Serverless 弹性**：CPU/内存可按秒级自动扩缩，空闲时自动暂停降低成本。
- **POLARDB_AUDIT_LOG**：内置审计日志，满足合规需求。

## 已知不足

- **仅阿里云可用**：无法在其他云平台或本地部署（开源版 PolarDB-PG 除外）。
- 共享存储架构下写入仍是单主节点瓶颈，写扩展需要分布式版本。
- 与 MySQL/PG 原生版本的兼容性在极少数边缘特性上存在差异。
- 分布式版（PolarDB-X）的使用复杂度高于单机版。
- 跨可用区部署的存储延迟比同区域部署有明显增加。
- 部分高级功能（如列存索引）需要特定规格实例才能使用。

## 对引擎开发者的参考价值

PolarDB 的共享存储架构是云原生数据库设计的重要范式之一，展示了如何利用分布式文件系统和 RDMA 网络实现存算分离。其物理复制 + 共享存储的只读扩展方案比传统逻辑复制更高效。列存索引（IMCI）在行存引擎上叠加分析能力的思路也被越来越多的数据库借鉴。PolarFS 的设计论文对分布式存储系统开发者有重要参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [polardb.sql](../ddl/create-table/polardb.sql) |
| 改表 | [polardb.sql](../ddl/alter-table/polardb.sql) |
| 索引 | [polardb.sql](../ddl/indexes/polardb.sql) |
| 约束 | [polardb.sql](../ddl/constraints/polardb.sql) |
| 视图 | [polardb.sql](../ddl/views/polardb.sql) |
| 序列与自增 | [polardb.sql](../ddl/sequences/polardb.sql) |
| 数据库/Schema/用户 | [polardb.sql](../ddl/users-databases/polardb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [polardb.sql](../advanced/dynamic-sql/polardb.sql) |
| 错误处理 | [polardb.sql](../advanced/error-handling/polardb.sql) |
| 执行计划 | [polardb.sql](../advanced/explain/polardb.sql) |
| 锁机制 | [polardb.sql](../advanced/locking/polardb.sql) |
| 分区 | [polardb.sql](../advanced/partitioning/polardb.sql) |
| 权限 | [polardb.sql](../advanced/permissions/polardb.sql) |
| 存储过程 | [polardb.sql](../advanced/stored-procedures/polardb.sql) |
| 临时表 | [polardb.sql](../advanced/temp-tables/polardb.sql) |
| 事务 | [polardb.sql](../advanced/transactions/polardb.sql) |
| 触发器 | [polardb.sql](../advanced/triggers/polardb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [polardb.sql](../dml/delete/polardb.sql) |
| 插入 | [polardb.sql](../dml/insert/polardb.sql) |
| 更新 | [polardb.sql](../dml/update/polardb.sql) |
| Upsert | [polardb.sql](../dml/upsert/polardb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [polardb.sql](../functions/aggregate/polardb.sql) |
| 条件函数 | [polardb.sql](../functions/conditional/polardb.sql) |
| 日期函数 | [polardb.sql](../functions/date-functions/polardb.sql) |
| 数学函数 | [polardb.sql](../functions/math-functions/polardb.sql) |
| 字符串函数 | [polardb.sql](../functions/string-functions/polardb.sql) |
| 类型转换 | [polardb.sql](../functions/type-conversion/polardb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [polardb.sql](../query/cte/polardb.sql) |
| 全文搜索 | [polardb.sql](../query/full-text-search/polardb.sql) |
| 连接查询 | [polardb.sql](../query/joins/polardb.sql) |
| 分页 | [polardb.sql](../query/pagination/polardb.sql) |
| 行列转换 | [polardb.sql](../query/pivot-unpivot/polardb.sql) |
| 集合操作 | [polardb.sql](../query/set-operations/polardb.sql) |
| 子查询 | [polardb.sql](../query/subquery/polardb.sql) |
| 窗口函数 | [polardb.sql](../query/window-functions/polardb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [polardb.sql](../scenarios/date-series-fill/polardb.sql) |
| 去重 | [polardb.sql](../scenarios/deduplication/polardb.sql) |
| 区间检测 | [polardb.sql](../scenarios/gap-detection/polardb.sql) |
| 层级查询 | [polardb.sql](../scenarios/hierarchical-query/polardb.sql) |
| JSON 展开 | [polardb.sql](../scenarios/json-flatten/polardb.sql) |
| 迁移速查 | [polardb.sql](../scenarios/migration-cheatsheet/polardb.sql) |
| TopN 查询 | [polardb.sql](../scenarios/ranking-top-n/polardb.sql) |
| 累计求和 | [polardb.sql](../scenarios/running-total/polardb.sql) |
| 缓慢变化维 | [polardb.sql](../scenarios/slowly-changing-dim/polardb.sql) |
| 字符串拆分 | [polardb.sql](../scenarios/string-split-to-rows/polardb.sql) |
| 窗口分析 | [polardb.sql](../scenarios/window-analytics/polardb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [polardb.sql](../types/array-map-struct/polardb.sql) |
| 日期时间 | [polardb.sql](../types/datetime/polardb.sql) |
| JSON | [polardb.sql](../types/json/polardb.sql) |
| 数值类型 | [polardb.sql](../types/numeric/polardb.sql) |
| 字符串类型 | [polardb.sql](../types/string/polardb.sql) |
