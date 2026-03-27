# Azure Synapse

**分类**: Azure 云数仓（基于 T-SQL）
**文件数**: 51 个 SQL 文件
**总行数**: 5000 行

## 概述与定位

Azure Synapse Analytics（前身为 Azure SQL Data Warehouse）是微软推出的云原生分析平台，将大规模数据仓库、数据湖集成、大数据分析和数据集成管道统一在一个服务中。其 SQL 引擎基于 T-SQL 方言，采用 MPP 架构处理 PB 级数据分析。Synapse 的核心优势是与 Azure 生态系统的深度集成——Azure Data Lake、Power BI、Azure ML 等服务可无缝协作。

## 历史与演进

- **2016 年**：Azure SQL Data Warehouse（SQL DW）正式发布，基于 MPP 架构提供 T-SQL 云数仓服务。
- **2018 年**：引入 Gen2 架构，支持无限存储扩展与自适应缓存（Adaptive Caching），计算存储分离。
- **2019 年**：品牌升级为 Azure Synapse Analytics，增加 Spark 池、Pipeline 集成和统一工作区（Synapse Studio）。
- **2020 年**：Synapse Serverless SQL pool 发布，支持按查询付费直接查询 Data Lake 中的文件。
- **2021 年**：引入 Synapse Link，实现从 Cosmos DB/Dataverse/SQL Server 到 Synapse 的近实时数据同步。
- **2023-2025 年**：增强与 Microsoft Fabric 的融合、改进 Lakehouse 格式支持（Delta Lake/Iceberg）、扩展 T-SQL 函数集。

## 核心设计思路

1. **MPP + T-SQL**：采用控制节点（Control Node）+ 计算节点（Compute Node）架构，SQL 查询被优化器拆分为分布式执行计划。
2. **数据分布策略**：建表时通过 `DISTRIBUTION = HASH(col) | ROUND_ROBIN | REPLICATE` 控制数据在计算节点间的分布方式。
3. **计算存储分离**：数据持久化在 Azure Storage 中，计算节点可独立扩缩容，暂停时仅收存储费用。
4. **统一分析平台**：Dedicated SQL pool（数仓）、Serverless SQL pool（数据湖查询）、Spark pool（大数据处理）在同一工作区共存。

## 独特特色

| 特性 | 说明 |
|---|---|
| **DISTRIBUTION** | `DISTRIBUTION = HASH(col)` 按哈希分布、`ROUND_ROBIN` 轮询分布、`REPLICATE` 全节点复制——三种策略直接影响 JOIN 性能。 |
| **CTAS（CREATE TABLE AS SELECT）** | 在 Synapse 中 CTAS 是最重要的数据转换模式，比 INSERT...SELECT 更高效，自动并行化。 |
| **PolyBase** | 通过外部表语法直接查询 Azure Blob Storage/ADLS/S3 中的 Parquet/CSV/ORC 文件，无需加载到数仓。 |
| **Result Set Caching** | 查询结果自动缓存在控制节点，相同查询直接返回缓存结果，无需重新执行分布式计划。 |
| **Workload Management** | 通过 Workload Groups 和 Workload Classifiers 对查询进行分类、资源分配和优先级排序。 |
| **Materialized Views** | 支持分布式物化视图，优化器可自动利用物化视图加速查询，无需手动改写 SQL。 |
| **Serverless SQL Pool** | 按查询扫描数据量付费，直接查询 Data Lake 文件，适合探索性分析和低频查询场景。 |

## 已知不足

- **T-SQL 子集限制**：与 SQL Server 的 T-SQL 并非完全兼容——不支持游标、触发器、跨数据库查询、部分系统函数。
- **索引受限**：不支持 B-tree 索引，仅支持列存储索引（Clustered Columnstore Index），行存索引仅用于 Heap 表。
- **UPDATE/DELETE 限制**：不支持带 FROM 子句的 UPDATE（需使用 CTAS + RENAME 模式替代），DML 操作限制较多。
- **唯一约束不强制**：主键和唯一约束仅为优化器提示，数据完整性需在 ETL 层保证。
- **暂停与恢复延迟**：Dedicated SQL pool 暂停/恢复需要数分钟，不如 Serverless 模式即时。
- **学习曲线**：分布策略选择、CTAS 模式、PolyBase 外部表配置对初学者有一定门槛。

## 对引擎开发者的参考价值

- **三种分布策略设计**：HASH/ROUND_ROBIN/REPLICATE 三种分布模式覆盖了分布式数仓的主要数据放置策略，对 MPP 引擎的数据分区设计有直接参考。
- **CTAS 优先的 ETL 模式**：将"建新表替换旧表"作为首选数据变换模式（而非 UPDATE in-place），对列存引擎的不可变数据设计有启发。
- **PolyBase 联邦查询**：通过统一的 SQL 语法查询异构数据源的外部表抽象，对查询引擎的联邦化改造有参考价值。
- **计算存储分离实践**：数据持久化在对象存储、计算节点无状态可伸缩的架构，是云原生数仓的标准范式。
- **Workload Management**：查询分类与资源隔离的机制设计，对多租户数仓引擎的资源调度有参考意义。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [synapse.sql](../ddl/create-table/synapse.sql) |
| 改表 | [synapse.sql](../ddl/alter-table/synapse.sql) |
| 索引 | [synapse.sql](../ddl/indexes/synapse.sql) |
| 约束 | [synapse.sql](../ddl/constraints/synapse.sql) |
| 视图 | [synapse.sql](../ddl/views/synapse.sql) |
| 序列与自增 | [synapse.sql](../ddl/sequences/synapse.sql) |
| 数据库/Schema/用户 | [synapse.sql](../ddl/users-databases/synapse.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [synapse.sql](../advanced/dynamic-sql/synapse.sql) |
| 错误处理 | [synapse.sql](../advanced/error-handling/synapse.sql) |
| 执行计划 | [synapse.sql](../advanced/explain/synapse.sql) |
| 锁机制 | [synapse.sql](../advanced/locking/synapse.sql) |
| 分区 | [synapse.sql](../advanced/partitioning/synapse.sql) |
| 权限 | [synapse.sql](../advanced/permissions/synapse.sql) |
| 存储过程 | [synapse.sql](../advanced/stored-procedures/synapse.sql) |
| 临时表 | [synapse.sql](../advanced/temp-tables/synapse.sql) |
| 事务 | [synapse.sql](../advanced/transactions/synapse.sql) |
| 触发器 | [synapse.sql](../advanced/triggers/synapse.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [synapse.sql](../dml/delete/synapse.sql) |
| 插入 | [synapse.sql](../dml/insert/synapse.sql) |
| 更新 | [synapse.sql](../dml/update/synapse.sql) |
| Upsert | [synapse.sql](../dml/upsert/synapse.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [synapse.sql](../functions/aggregate/synapse.sql) |
| 条件函数 | [synapse.sql](../functions/conditional/synapse.sql) |
| 日期函数 | [synapse.sql](../functions/date-functions/synapse.sql) |
| 数学函数 | [synapse.sql](../functions/math-functions/synapse.sql) |
| 字符串函数 | [synapse.sql](../functions/string-functions/synapse.sql) |
| 类型转换 | [synapse.sql](../functions/type-conversion/synapse.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [synapse.sql](../query/cte/synapse.sql) |
| 全文搜索 | [synapse.sql](../query/full-text-search/synapse.sql) |
| 连接查询 | [synapse.sql](../query/joins/synapse.sql) |
| 分页 | [synapse.sql](../query/pagination/synapse.sql) |
| 行列转换 | [synapse.sql](../query/pivot-unpivot/synapse.sql) |
| 集合操作 | [synapse.sql](../query/set-operations/synapse.sql) |
| 子查询 | [synapse.sql](../query/subquery/synapse.sql) |
| 窗口函数 | [synapse.sql](../query/window-functions/synapse.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [synapse.sql](../scenarios/date-series-fill/synapse.sql) |
| 去重 | [synapse.sql](../scenarios/deduplication/synapse.sql) |
| 区间检测 | [synapse.sql](../scenarios/gap-detection/synapse.sql) |
| 层级查询 | [synapse.sql](../scenarios/hierarchical-query/synapse.sql) |
| JSON 展开 | [synapse.sql](../scenarios/json-flatten/synapse.sql) |
| 迁移速查 | [synapse.sql](../scenarios/migration-cheatsheet/synapse.sql) |
| TopN 查询 | [synapse.sql](../scenarios/ranking-top-n/synapse.sql) |
| 累计求和 | [synapse.sql](../scenarios/running-total/synapse.sql) |
| 缓慢变化维 | [synapse.sql](../scenarios/slowly-changing-dim/synapse.sql) |
| 字符串拆分 | [synapse.sql](../scenarios/string-split-to-rows/synapse.sql) |
| 窗口分析 | [synapse.sql](../scenarios/window-analytics/synapse.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [synapse.sql](../types/array-map-struct/synapse.sql) |
| 日期时间 | [synapse.sql](../types/datetime/synapse.sql) |
| JSON | [synapse.sql](../types/json/synapse.sql) |
| 数值类型 | [synapse.sql](../types/numeric/synapse.sql) |
| 字符串类型 | [synapse.sql](../types/string/synapse.sql) |
