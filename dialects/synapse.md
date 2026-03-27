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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/synapse.sql) | Azure MPP 数仓(SQL Server 方言)，DISTRIBUTION 决定分布 |
| [改表](../ddl/alter-table/synapse.sql) | ALTER 受限，不支持大部分在线变更 |
| [索引](../ddl/indexes/synapse.sql) | Clustered Columnstore 默认，Heap/Clustered Rowstore 可选 |
| [约束](../ddl/constraints/synapse.sql) | PK/FK/UNIQUE 声明但不强制(同 BigQuery/Redshift) |
| [视图](../ddl/views/synapse.sql) | 普通视图+物化视图(自动刷新)，RESULT_SET_CACHING |
| [序列与自增](../ddl/sequences/synapse.sql) | IDENTITY 自增列，无 SEQUENCE |
| [数据库/Schema/用户](../ddl/users-databases/synapse.sql) | T-SQL 兼容权限，Azure AD 集成 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/synapse.sql) | sp_executesql/EXEC(T-SQL 兼容) |
| [错误处理](../advanced/error-handling/synapse.sql) | TRY...CATCH(T-SQL 兼容) |
| [执行计划](../advanced/explain/synapse.sql) | EXPLAIN(分布式 MPP 计划)，DMV 性能视图 |
| [锁机制](../advanced/locking/synapse.sql) | 无行级锁(MPP 列存)，并发限制通过 Resource Class |
| [分区](../advanced/partitioning/synapse.sql) | DISTRIBUTION(HASH/ROUND_ROBIN/REPLICATE) 分布策略 |
| [权限](../advanced/permissions/synapse.sql) | T-SQL 兼容+Azure AD+Row-Level Security |
| [存储过程](../advanced/stored-procedures/synapse.sql) | T-SQL 存储过程(功能子集)，不支持嵌套/递归 |
| [临时表](../advanced/temp-tables/synapse.sql) | #temp(T-SQL 兼容)，CETAS 替代 |
| [事务](../advanced/transactions/synapse.sql) | ACID(受限)，不支持嵌套事务，DDL 事务有限 |
| [触发器](../advanced/triggers/synapse.sql) | 不支持触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/synapse.sql) | DELETE(T-SQL 兼容)，CTAS+RENAME 替代大批量删除 |
| [插入](../dml/insert/synapse.sql) | INSERT+COPY INTO(推荐批量加载)，PolyBase 外部数据 |
| [更新](../dml/update/synapse.sql) | UPDATE(T-SQL 兼容)，大表更新建议 CTAS 重建 |
| [Upsert](../dml/upsert/synapse.sql) | MERGE(T-SQL 兼容)，适用于维度表更新 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/synapse.sql) | STRING_AGG，APPROX_COUNT_DISTINCT，T-SQL 兼容 |
| [条件函数](../functions/conditional/synapse.sql) | IIF/CASE/COALESCE(T-SQL 兼容) |
| [日期函数](../functions/date-functions/synapse.sql) | DATEADD/DATEDIFF/EOMONTH(T-SQL 兼容) |
| [数学函数](../functions/math-functions/synapse.sql) | T-SQL 兼容数学函数 |
| [字符串函数](../functions/string-functions/synapse.sql) | STRING_SPLIT/CONCAT_WS(T-SQL 兼容) |
| [类型转换](../functions/type-conversion/synapse.sql) | TRY_CAST/TRY_CONVERT(T-SQL 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/synapse.sql) | WITH 标准+递归(有限制)，T-SQL 兼容 |
| [全文搜索](../query/full-text-search/synapse.sql) | 不支持全文搜索 |
| [连接查询](../query/joins/synapse.sql) | Broadcast/Shuffle/Replicated JOIN，分布策略决定性能 |
| [分页](../query/pagination/synapse.sql) | OFFSET...FETCH(T-SQL 兼容) |
| [行列转换](../query/pivot-unpivot/synapse.sql) | PIVOT/UNPIVOT(T-SQL 兼容) |
| [集合操作](../query/set-operations/synapse.sql) | UNION/INTERSECT/EXCEPT(T-SQL 兼容) |
| [子查询](../query/subquery/synapse.sql) | 关联子查询(T-SQL 兼容) |
| [窗口函数](../query/window-functions/synapse.sql) | 完整窗口函数(T-SQL 兼容)，列存加速 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/synapse.sql) | 递归 CTE 或数字表(T-SQL 兼容) |
| [去重](../scenarios/deduplication/synapse.sql) | ROW_NUMBER+CTE(T-SQL 兼容) |
| [区间检测](../scenarios/gap-detection/synapse.sql) | 窗口函数(T-SQL 兼容) |
| [层级查询](../scenarios/hierarchical-query/synapse.sql) | 递归 CTE(有限制) |
| [JSON 展开](../scenarios/json-flatten/synapse.sql) | OPENJSON(T-SQL 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/synapse.sql) | T-SQL 子集，DISTRIBUTION 策略+列存是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/synapse.sql) | ROW_NUMBER+TOP(T-SQL 兼容) |
| [累计求和](../scenarios/running-total/synapse.sql) | SUM() OVER(T-SQL 兼容)，列存加速 |
| [缓慢变化维](../scenarios/slowly-changing-dim/synapse.sql) | MERGE(T-SQL 兼容)，CTAS 重建替代 |
| [字符串拆分](../scenarios/string-split-to-rows/synapse.sql) | STRING_SPLIT(T-SQL 兼容) |
| [窗口分析](../scenarios/window-analytics/synapse.sql) | 完整窗口函数(T-SQL 兼容)，MPP 并行 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/synapse.sql) | 无原生数组，JSON 替代(T-SQL 兼容) |
| [日期时间](../types/datetime/synapse.sql) | datetime2/date/time(T-SQL 兼容) |
| [JSON](../types/json/synapse.sql) | JSON 存为 NVARCHAR(T-SQL 兼容)，OPENJSON 解析 |
| [数值类型](../types/numeric/synapse.sql) | T-SQL 兼容数值类型，DECIMAL/FLOAT |
| [字符串类型](../types/string/synapse.sql) | VARCHAR/NVARCHAR(T-SQL 兼容)，Collation |
