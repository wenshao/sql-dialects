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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/polardb.sql) | MySQL 高度兼容(阿里云)，计算存储分离，读写分离透明 |
| [改表](../ddl/alter-table/polardb.sql) | Online DDL(MySQL 兼容)，Parallel DDL 加速 |
| [索引](../ddl/indexes/polardb.sql) | InnoDB 索引(MySQL 兼容)，并行构建索引 |
| [约束](../ddl/constraints/polardb.sql) | PK/FK/CHECK(MySQL 兼容)，CHECK(8.0 兼容) |
| [视图](../ddl/views/polardb.sql) | MySQL 兼容视图，无物化视图 |
| [序列与自增](../ddl/sequences/polardb.sql) | AUTO_INCREMENT(MySQL 兼容)，全局自增保证 |
| [数据库/Schema/用户](../ddl/users-databases/polardb.sql) | MySQL 兼容权限模型 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/polardb.sql) | PREPARE/EXECUTE(MySQL 兼容) |
| [错误处理](../advanced/error-handling/polardb.sql) | DECLARE HANDLER(MySQL 兼容) |
| [执行计划](../advanced/explain/polardb.sql) | EXPLAIN ANALYZE(MySQL 兼容)，并行查询计划 |
| [锁机制](../advanced/locking/polardb.sql) | InnoDB 行锁(MySQL 兼容)，全局一致性读(存储层) |
| [分区](../advanced/partitioning/polardb.sql) | RANGE/LIST/HASH(MySQL 兼容)，分区表并行扫描 |
| [权限](../advanced/permissions/polardb.sql) | MySQL 兼容权限模型 |
| [存储过程](../advanced/stored-procedures/polardb.sql) | MySQL 兼容存储过程 |
| [临时表](../advanced/temp-tables/polardb.sql) | TEMPORARY TABLE(MySQL 兼容) |
| [事务](../advanced/transactions/polardb.sql) | InnoDB MVCC(MySQL 兼容)，计算存储分离下强一致 |
| [触发器](../advanced/triggers/polardb.sql) | MySQL 兼容触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/polardb.sql) | DELETE(MySQL 兼容)，Parallel DML 加速 |
| [插入](../dml/insert/polardb.sql) | INSERT(MySQL 兼容)，Parallel INSERT 加速 |
| [更新](../dml/update/polardb.sql) | UPDATE(MySQL 兼容)，Parallel DML |
| [Upsert](../dml/upsert/polardb.sql) | ON DUPLICATE KEY UPDATE(MySQL 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/polardb.sql) | MySQL 兼容聚合，并行聚合加速 |
| [条件函数](../functions/conditional/polardb.sql) | IF/CASE(MySQL 兼容) |
| [日期函数](../functions/date-functions/polardb.sql) | MySQL 兼容日期函数 |
| [数学函数](../functions/math-functions/polardb.sql) | MySQL 兼容数学函数 |
| [字符串函数](../functions/string-functions/polardb.sql) | MySQL 兼容字符串函数 |
| [类型转换](../functions/type-conversion/polardb.sql) | CAST/CONVERT(MySQL 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/polardb.sql) | 递归 CTE(MySQL 8.0 兼容) |
| [全文搜索](../query/full-text-search/polardb.sql) | InnoDB FULLTEXT(MySQL 兼容)，ngram |
| [连接查询](../query/joins/polardb.sql) | MySQL 兼容 JOIN+Parallel Hash JOIN 加速 |
| [分页](../query/pagination/polardb.sql) | LIMIT/OFFSET(MySQL 兼容) |
| [行列转换](../query/pivot-unpivot/polardb.sql) | 无原生 PIVOT(同 MySQL) |
| [集合操作](../query/set-operations/polardb.sql) | UNION/INTERSECT/EXCEPT(MySQL 8.0 兼容) |
| [子查询](../query/subquery/polardb.sql) | MySQL 兼容子查询优化+并行加速 |
| [窗口函数](../query/window-functions/polardb.sql) | MySQL 8.0 兼容窗口函数+并行执行 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/polardb.sql) | 递归 CTE(MySQL 兼容) 生成日期序列 |
| [去重](../scenarios/deduplication/polardb.sql) | ROW_NUMBER+CTE(MySQL 兼容) |
| [区间检测](../scenarios/gap-detection/polardb.sql) | 窗口函数(MySQL 兼容) |
| [层级查询](../scenarios/hierarchical-query/polardb.sql) | 递归 CTE(MySQL 兼容) |
| [JSON 展开](../scenarios/json-flatten/polardb.sql) | JSON_TABLE(MySQL 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/polardb.sql) | MySQL 高度兼容，计算存储分离+并行查询是核心增值 |
| [TopN 查询](../scenarios/ranking-top-n/polardb.sql) | ROW_NUMBER+LIMIT(MySQL 兼容) |
| [累计求和](../scenarios/running-total/polardb.sql) | SUM() OVER(MySQL 兼容)+并行 |
| [缓慢变化维](../scenarios/slowly-changing-dim/polardb.sql) | ON DUPLICATE KEY UPDATE(MySQL 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/polardb.sql) | JSON_TABLE 或递归 CTE(MySQL 兼容) |
| [窗口分析](../scenarios/window-analytics/polardb.sql) | MySQL 兼容窗口函数+并行加速 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/polardb.sql) | 无 ARRAY/STRUCT，JSON 替代(MySQL 兼容) |
| [日期时间](../types/datetime/polardb.sql) | DATETIME/TIMESTAMP(MySQL 兼容) |
| [JSON](../types/json/polardb.sql) | JSON 二进制存储(MySQL 兼容)，多值索引 |
| [数值类型](../types/numeric/polardb.sql) | MySQL 兼容数值类型 |
| [字符串类型](../types/string/polardb.sql) | utf8mb4 推荐(MySQL 兼容) |
