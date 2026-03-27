# StarRocks

**分类**: MPP 分析数据库
**文件数**: 51 个 SQL 文件
**总行数**: 4301 行

## 概述与定位

StarRocks 是一款高性能 MPP 分析数据库，2020 年从 Apache Doris 分叉而来（最初名为 DorisDB），由 StarRocks Inc. 主导开发。StarRocks 定位于"极速统一分析"——在一个引擎中同时满足实时分析、Ad-hoc 查询、多维报表和数据湖分析需求。它以向量化执行引擎、CBO 优化器和灵活的存储模型为核心竞争力，在中国互联网、电商、游戏和金融行业有快速增长的用户群。

## 历史与演进

- **2020 年**：从 Apache Doris 分叉，以 DorisDB 品牌独立开发，重构优化器和执行引擎。
- **2021 年**：更名为 StarRocks，开源（Apache 2.0 许可），1.x 版本引入全新 CBO 优化器。
- **2022 年**：2.x 版本引入 Primary Key 模型（实时更新）、外部表支持（Hive/Iceberg/Hudi）、资源组。
- **2023 年**：3.x 版本引入存算分离架构、共享数据（Shared-Data）模式、物化视图增强、数据湖分析加速。
- **2024-2025 年**：推进 AI 集成（向量索引）、增强半结构化数据处理（JSON/Struct/Map/Array）、Pipe 持续数据加载。

## 核心设计思路

1. **FE + BE 架构**：FE（Frontend）负责 SQL 解析、CBO 优化和元数据管理，BE（Backend）负责数据存储和向量化执行。
2. **四种数据模型**：Duplicate Key（明细保留）、Aggregate Key（预聚合）、Unique Key（唯一键最新值）、Primary Key（主键实时更新），每种模型对应不同的写入和查询模式。
3. **全面向量化**：从存储层扫描到所有算子（JOIN、聚合、排序、窗口函数）均基于列式向量化执行，利用 SIMD 指令加速。
4. **CBO 优化器**：自研的基于 Cascades 框架的成本优化器，支持 Join Reorder、子查询去关联、相关子查询优化等高级变换。

## 独特特色

| 特性 | 说明 |
|---|---|
| **四种数据模型** | Duplicate Key（全量明细）、Aggregate Key（SUM/MAX/MIN/REPLACE 预聚合）、Unique Key（去重取最新）、Primary Key（支持实时 UPDATE/DELETE）。 |
| **物化视图** | 支持同步和异步物化视图，CBO 可自动改写查询命中物化视图，支持基于外部表的物化视图。 |
| **向量化执行** | 全链路向量化——扫描、表达式计算、聚合、JOIN、排序均在列式向量上操作，减少虚函数调用和内存拷贝。 |
| **存算分离（Shared-Data）** | 数据持久化在对象存储（S3/OSS/GCS），BE 节点无状态可弹性伸缩，本地 SSD 作缓存层。 |
| **多源联邦查询** | 通过 Catalog 机制直接查询 Hive/Iceberg/Hudi/Delta Lake/MySQL/PostgreSQL/Elasticsearch 等数据源。 |
| **Global Runtime Filter** | 跨 Fragment 的全局 Runtime Filter，在分布式 JOIN 中将 Build 侧的 Filter 广播到所有 Probe 侧节点。 |
| **Pipe 持续加载** | `CREATE PIPE` 实现从对象存储到 StarRocks 的持续自动数据加载，类似 Snowpipe。 |

## 已知不足

- **事务支持有限**：不支持传统 RDBMS 的多语句事务，每次数据导入（Load）是一个原子操作。
- **与 Doris 的竞争混淆**：与 Apache Doris 同源且功能高度重合，社区用户在选型时经常困惑。
- **存储过程缺失**：不支持存储过程、触发器和游标，复杂业务逻辑需在应用层实现。
- **单表规模限制**：虽然是 MPP 架构，但单表数据规模超过数百亿行后，分桶和分区策略的调优难度增大。
- **UPDATE/DELETE 模型限制**：仅 Primary Key / Unique Key 模型支持行级变更，Duplicate / Aggregate 模型不支持。

## 对引擎开发者的参考价值

- **Cascades CBO 实现**：StarRocks 的优化器基于 Columbia/Cascades 框架，其 Rule 设计和 Cost Model 实现对自研优化器有直接参考。
- **全链路向量化实践**：从 Scan 到 Sink 所有算子均基于列式批处理的实现，展示了彻底向量化的性能收益和工程挑战。
- **Primary Key 模型**：基于 Delete + Insert 的实时更新模型（Merge-on-Read / Merge-on-Write），对实时可变列存表的设计有参考。
- **Global Runtime Filter**：跨节点广播 Bloom Filter / Min-Max Filter 的分布式实现，是优化星型模型查询的关键技术。
- **存算分离 + 缓存层**：数据在对象存储、BE 本地 SSD 作为 Cache 的分层存储设计，对云原生分析引擎有直接参考。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [starrocks.sql](../ddl/create-table/starrocks.sql) |
| 改表 | [starrocks.sql](../ddl/alter-table/starrocks.sql) |
| 索引 | [starrocks.sql](../ddl/indexes/starrocks.sql) |
| 约束 | [starrocks.sql](../ddl/constraints/starrocks.sql) |
| 视图 | [starrocks.sql](../ddl/views/starrocks.sql) |
| 序列与自增 | [starrocks.sql](../ddl/sequences/starrocks.sql) |
| 数据库/Schema/用户 | [starrocks.sql](../ddl/users-databases/starrocks.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [starrocks.sql](../advanced/dynamic-sql/starrocks.sql) |
| 错误处理 | [starrocks.sql](../advanced/error-handling/starrocks.sql) |
| 执行计划 | [starrocks.sql](../advanced/explain/starrocks.sql) |
| 锁机制 | [starrocks.sql](../advanced/locking/starrocks.sql) |
| 分区 | [starrocks.sql](../advanced/partitioning/starrocks.sql) |
| 权限 | [starrocks.sql](../advanced/permissions/starrocks.sql) |
| 存储过程 | [starrocks.sql](../advanced/stored-procedures/starrocks.sql) |
| 临时表 | [starrocks.sql](../advanced/temp-tables/starrocks.sql) |
| 事务 | [starrocks.sql](../advanced/transactions/starrocks.sql) |
| 触发器 | [starrocks.sql](../advanced/triggers/starrocks.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [starrocks.sql](../dml/delete/starrocks.sql) |
| 插入 | [starrocks.sql](../dml/insert/starrocks.sql) |
| 更新 | [starrocks.sql](../dml/update/starrocks.sql) |
| Upsert | [starrocks.sql](../dml/upsert/starrocks.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [starrocks.sql](../functions/aggregate/starrocks.sql) |
| 条件函数 | [starrocks.sql](../functions/conditional/starrocks.sql) |
| 日期函数 | [starrocks.sql](../functions/date-functions/starrocks.sql) |
| 数学函数 | [starrocks.sql](../functions/math-functions/starrocks.sql) |
| 字符串函数 | [starrocks.sql](../functions/string-functions/starrocks.sql) |
| 类型转换 | [starrocks.sql](../functions/type-conversion/starrocks.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [starrocks.sql](../query/cte/starrocks.sql) |
| 全文搜索 | [starrocks.sql](../query/full-text-search/starrocks.sql) |
| 连接查询 | [starrocks.sql](../query/joins/starrocks.sql) |
| 分页 | [starrocks.sql](../query/pagination/starrocks.sql) |
| 行列转换 | [starrocks.sql](../query/pivot-unpivot/starrocks.sql) |
| 集合操作 | [starrocks.sql](../query/set-operations/starrocks.sql) |
| 子查询 | [starrocks.sql](../query/subquery/starrocks.sql) |
| 窗口函数 | [starrocks.sql](../query/window-functions/starrocks.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [starrocks.sql](../scenarios/date-series-fill/starrocks.sql) |
| 去重 | [starrocks.sql](../scenarios/deduplication/starrocks.sql) |
| 区间检测 | [starrocks.sql](../scenarios/gap-detection/starrocks.sql) |
| 层级查询 | [starrocks.sql](../scenarios/hierarchical-query/starrocks.sql) |
| JSON 展开 | [starrocks.sql](../scenarios/json-flatten/starrocks.sql) |
| 迁移速查 | [starrocks.sql](../scenarios/migration-cheatsheet/starrocks.sql) |
| TopN 查询 | [starrocks.sql](../scenarios/ranking-top-n/starrocks.sql) |
| 累计求和 | [starrocks.sql](../scenarios/running-total/starrocks.sql) |
| 缓慢变化维 | [starrocks.sql](../scenarios/slowly-changing-dim/starrocks.sql) |
| 字符串拆分 | [starrocks.sql](../scenarios/string-split-to-rows/starrocks.sql) |
| 窗口分析 | [starrocks.sql](../scenarios/window-analytics/starrocks.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [starrocks.sql](../types/array-map-struct/starrocks.sql) |
| 日期时间 | [starrocks.sql](../types/datetime/starrocks.sql) |
| JSON | [starrocks.sql](../types/json/starrocks.sql) |
| 数值类型 | [starrocks.sql](../types/numeric/starrocks.sql) |
| 字符串类型 | [starrocks.sql](../types/string/starrocks.sql) |
