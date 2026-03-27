# Amazon Redshift

**分类**: AWS 云数仓（基于 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4862 行

## 概述与定位

Amazon Redshift 是 AWS 推出的全托管云数据仓库服务，基于 ParAccel（PostgreSQL 8.0.2 分叉）演化而来。它将 MPP（大规模并行处理）架构与列式存储相结合，面向 PB 级数据的交互式分析查询。Redshift 是云数仓赛道的先行者（2012 年发布），凭借"按需付费 + 与 AWS 生态深度集成"的模式迅速成为最广泛使用的云数仓之一。

## 历史与演进

- **2012 年**：Redshift 正式发布（GA），基于 ParAccel 的列式 MPP 引擎，提供 PostgreSQL 8.x 兼容的 SQL 接口。
- **2015 年**：引入 Redshift Spectrum，支持直接查询 S3 上的数据而无需加载到集群本地。
- **2018 年**：引入弹性调整（Elastic Resize）、并发扩展（Concurrency Scaling）、结果集缓存。
- **2019 年**：发布 AQUA（Advanced Query Accelerator），在存储层嵌入硬件加速查询处理。
- **2020 年**：引入 RA3 节点类型，实现计算与存储分离（托管存储基于 S3）。
- **2021 年**：Redshift Serverless 发布，用户无需管理集群即可按查询量付费。
- **2022 年**：引入 SUPER 半结构化数据类型、多数仓数据共享（Data Sharing）。
- **2023-2025 年**：增强 MERGE 支持、增量物化视图刷新、零 ETL 集成（Aurora/DynamoDB 到 Redshift 自动复制）。

## 核心设计思路

1. **列式存储 + MPP**：数据按列存储并自动压缩，查询被分发到多个计算节点并行执行。
2. **分布键与排序键**：DISTKEY 控制数据在节点间的分布策略（减少数据倾斜和网络传输），SORTKEY 控制磁盘上的物理排序（加速范围扫描和 Zone Map 裁剪）。
3. **深度 AWS 集成**：COPY 命令从 S3/DynamoDB/EMR 批量加载数据，UNLOAD 导出到 S3，Spectrum 联邦查询 S3 数据湖。
4. **计算存储分离**：RA3 节点类型使用托管存储（Redshift Managed Storage），热数据缓存在本地 SSD，冷数据自动落到 S3。

## 独特特色

| 特性 | 说明 |
|---|---|
| **DISTKEY / SORTKEY** | 建表时指定 `DISTKEY(col)` 和 `SORTKEY(col1, col2)`，直接控制数据的物理分布和排序，是查询调优的核心手段。 |
| **COPY from S3** | 高吞吐批量加载命令，支持 CSV/JSON/Parquet/ORC 格式，自动并行从 S3 多个文件加载到多个切片。 |
| **SUPER 类型** | 半结构化数据类型，存储 JSON/数组/对象，支持 PartiQL 语法查询（如 `s.address.city`），无需预定义 schema。 |
| **Redshift Spectrum** | 在 SQL 中直接查询 S3 上的外部表（Parquet/ORC/CSV），与本地表 JOIN，实现数据湖与数仓的联邦查询。 |
| **Concurrency Scaling** | 查询并发超过集群能力时自动弹出临时集群处理溢出查询，用户无感知。 |
| **Zone Map** | 自动维护每个 1MB 磁盘块的 min/max 元数据，配合 SORTKEY 实现高效的块级过滤。 |
| **Data Sharing** | 多个 Redshift 集群/Serverless 实例之间实时共享数据，无需复制或 ETL。 |

## 已知不足

- **PostgreSQL 兼容性有限**：基于 PG 8.x 分叉，不支持 PG 的许多现代特性——无存储过程（仅 UDF）、无触发器、无 GIN/GiST 索引、无数组类型。
- **UPDATE/DELETE 开销大**：列式存储下行级更新代价高，频繁小批量写入性能差，需定期 VACUUM 回收空间。
- **主键/外键不强制**：约束仅作为优化器提示，不实际校验数据完整性，可能导致数据质量问题。
- **存储过程支持较晚**：2018 年才引入 PL/pgSQL 存储过程，功能仍不如原生 PostgreSQL 完备。
- **SORTKEY 选择困难**：Compound SORTKEY 只对前缀列有效，Interleaved SORTKEY 的 VACUUM 开销大，调优需仔细权衡。

## 对引擎开发者的参考价值

- **DISTKEY/SORTKEY 模型**：将数据分布和物理排序决策暴露为 DDL 语法，是分布式查询引擎设计中数据布局策略的经典实现。
- **Zone Map 过滤**：每个存储块自动维护列的 min/max，在查询时进行块级剪枝——实现简单但效果显著，值得任何列存引擎借鉴。
- **COPY 的并行加载架构**：将外部文件切分后并行加载到多个计算切片的 pipeline 设计，对批量导入优化有重要参考。
- **SUPER 类型与 PartiQL**：在列存引擎中支持半结构化数据的存储与查询，展示了严格 schema 与灵活 schema 的折中方案。
- **Concurrency Scaling 弹性模型**：查询溢出时自动启动临时计算资源的架构，对云原生数仓的弹性设计有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [redshift.sql](../ddl/create-table/redshift.sql) |
| 改表 | [redshift.sql](../ddl/alter-table/redshift.sql) |
| 索引 | [redshift.sql](../ddl/indexes/redshift.sql) |
| 约束 | [redshift.sql](../ddl/constraints/redshift.sql) |
| 视图 | [redshift.sql](../ddl/views/redshift.sql) |
| 序列与自增 | [redshift.sql](../ddl/sequences/redshift.sql) |
| 数据库/Schema/用户 | [redshift.sql](../ddl/users-databases/redshift.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [redshift.sql](../advanced/dynamic-sql/redshift.sql) |
| 错误处理 | [redshift.sql](../advanced/error-handling/redshift.sql) |
| 执行计划 | [redshift.sql](../advanced/explain/redshift.sql) |
| 锁机制 | [redshift.sql](../advanced/locking/redshift.sql) |
| 分区 | [redshift.sql](../advanced/partitioning/redshift.sql) |
| 权限 | [redshift.sql](../advanced/permissions/redshift.sql) |
| 存储过程 | [redshift.sql](../advanced/stored-procedures/redshift.sql) |
| 临时表 | [redshift.sql](../advanced/temp-tables/redshift.sql) |
| 事务 | [redshift.sql](../advanced/transactions/redshift.sql) |
| 触发器 | [redshift.sql](../advanced/triggers/redshift.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [redshift.sql](../dml/delete/redshift.sql) |
| 插入 | [redshift.sql](../dml/insert/redshift.sql) |
| 更新 | [redshift.sql](../dml/update/redshift.sql) |
| Upsert | [redshift.sql](../dml/upsert/redshift.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [redshift.sql](../functions/aggregate/redshift.sql) |
| 条件函数 | [redshift.sql](../functions/conditional/redshift.sql) |
| 日期函数 | [redshift.sql](../functions/date-functions/redshift.sql) |
| 数学函数 | [redshift.sql](../functions/math-functions/redshift.sql) |
| 字符串函数 | [redshift.sql](../functions/string-functions/redshift.sql) |
| 类型转换 | [redshift.sql](../functions/type-conversion/redshift.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [redshift.sql](../query/cte/redshift.sql) |
| 全文搜索 | [redshift.sql](../query/full-text-search/redshift.sql) |
| 连接查询 | [redshift.sql](../query/joins/redshift.sql) |
| 分页 | [redshift.sql](../query/pagination/redshift.sql) |
| 行列转换 | [redshift.sql](../query/pivot-unpivot/redshift.sql) |
| 集合操作 | [redshift.sql](../query/set-operations/redshift.sql) |
| 子查询 | [redshift.sql](../query/subquery/redshift.sql) |
| 窗口函数 | [redshift.sql](../query/window-functions/redshift.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [redshift.sql](../scenarios/date-series-fill/redshift.sql) |
| 去重 | [redshift.sql](../scenarios/deduplication/redshift.sql) |
| 区间检测 | [redshift.sql](../scenarios/gap-detection/redshift.sql) |
| 层级查询 | [redshift.sql](../scenarios/hierarchical-query/redshift.sql) |
| JSON 展开 | [redshift.sql](../scenarios/json-flatten/redshift.sql) |
| 迁移速查 | [redshift.sql](../scenarios/migration-cheatsheet/redshift.sql) |
| TopN 查询 | [redshift.sql](../scenarios/ranking-top-n/redshift.sql) |
| 累计求和 | [redshift.sql](../scenarios/running-total/redshift.sql) |
| 缓慢变化维 | [redshift.sql](../scenarios/slowly-changing-dim/redshift.sql) |
| 字符串拆分 | [redshift.sql](../scenarios/string-split-to-rows/redshift.sql) |
| 窗口分析 | [redshift.sql](../scenarios/window-analytics/redshift.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [redshift.sql](../types/array-map-struct/redshift.sql) |
| 日期时间 | [redshift.sql](../types/datetime/redshift.sql) |
| JSON | [redshift.sql](../types/json/redshift.sql) |
| 数值类型 | [redshift.sql](../types/numeric/redshift.sql) |
| 字符串类型 | [redshift.sql](../types/string/redshift.sql) |
