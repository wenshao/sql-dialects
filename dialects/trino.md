# Trino

**分类**: 分布式查询引擎
**文件数**: 51 个 SQL 文件
**总行数**: 4552 行

## 概述与定位

Trino（原 PrestoSQL）是一款开源的分布式 SQL 查询引擎，最初由 Facebook 的 Martin Traverso、Dain Sundstrom、David Phillips 和 Eric Hwang 于 2012 年创建。Trino 的核心理念是"一个引擎查所有数据"——通过 Connector 插件化架构，用统一的 ANSI SQL 查询分布在不同系统中的数据（Hive、MySQL、PostgreSQL、Kafka、Elasticsearch、S3 等），无需将数据搬运到统一的数仓中。Trino 不存储数据，它是纯粹的计算引擎。

## 历史与演进

- **2012 年**：Facebook 内部启动 Presto 项目，解决 Hive MapReduce 查询延迟过高的问题。
- **2013 年**：Presto 开源（Apache 许可），迅速在 Netflix、Uber、Airbnb 等公司获得采用。
- **2019 年**：创始团队离开 Facebook 成立 Starburst 公司，将项目更名为 PrestoSQL（后更名 Trino），与 Facebook 维护的 PrestoDB 正式分道。
- **2020 年**：正式更名为 Trino（商标原因），社区版本号重置。
- **2022 年**：引入 Fault-Tolerant Execution（容错执行模式），支持中间结果落盘和任务重试。
- **2023 年**：增强 Iceberg/Delta Lake/Hudi 连接器、改进动态过滤、引入多语句查询支持。
- **2024-2025 年**：持续优化大规模查询（ETL 场景）的稳定性、增强物化视图和缓存层。

## 核心设计思路

1. **Connector 架构**：每个数据源通过实现 Connector SPI 接口接入 Trino，SQL 引擎与存储完全解耦。一条 SQL 可 JOIN 来自不同数据源的表。
2. **MPP 管道式执行**：查询被拆分为多个 Stage，Stage 内多个 Task 分布到 Worker 节点并行执行，数据以管道流（Pipeline）方式在算子间流动，无需落盘中间结果（Fault-Tolerant 模式除外）。
3. **联邦查询**：用 `catalog.schema.table` 三级命名空间引用不同数据源的表，可在一条 SQL 中跨数据源 JOIN。
4. **ANSI SQL 兼容**：SQL 方言高度遵循 ANSI SQL 标准，支持复杂查询（窗口函数、CTE、LATERAL、UNNEST、Lambda）。

## 独特特色

| 特性 | 说明 |
|---|---|
| **Connector 架构** | 插件化数据源接入——Hive、Iceberg、Delta Lake、MySQL、PostgreSQL、MongoDB、Kafka、Elasticsearch 等数十种 Connector。 |
| **联邦查询** | `SELECT * FROM hive.db.t1 JOIN mysql.db.t2 ON ...`，在一条 SQL 中 JOIN 不同数据源的表。 |
| **UNNEST** | `SELECT * FROM t CROSS JOIN UNNEST(array_col) AS u(element)` 将数组/Map 展开为行，是处理嵌套数据的核心手段。 |
| **Lambda 表达式** | `transform(array, x -> x * 2)` / `filter(array, x -> x > 0)` 等高阶函数，对数组/Map 进行函数式操作。 |
| **动态过滤** | Join 的 Build 侧运行时生成过滤条件下推到 Probe 侧的 TableScan，减少大表扫描量。 |
| **Fault-Tolerant Execution** | 中间结果可落盘（Spill to Exchange），Task 失败后可重试而非整个查询失败，适合 ETL 级长查询。 |
| **Session 属性** | 通过 `SET SESSION property = value` 灵活控制查询行为（如 `join_distribution_type`、`task_concurrency`）。 |

## 已知不足

- **不存储数据**：Trino 是纯计算引擎，查询性能受限于底层数据源的 I/O 和格式，对于非列式格式（如 CSV、JSON）查询效率较低。
- **UPDATE/DELETE 有限**：仅部分 Connector（如 Iceberg、Hive ACID、JDBC）支持行级变更，大部分 Connector 只支持 SELECT/INSERT。
- **存储过程/触发器缺失**：作为查询引擎不支持存储过程、触发器等过程化编程特性。
- **资源管理较弱**：内置的资源组（Resource Groups）功能相对基础，不如专业数仓的 Workload Management 精细。
- **Coordinator 单点**：Coordinator 是单点（虽有故障恢复机制），在超大规模集群中可能成为瓶颈。
- **元数据缓存一致性**：对频繁变更的数据源，Connector 的元数据缓存可能导致查询到过期的 schema 或统计信息。

## 对引擎开发者的参考价值

- **Connector SPI 设计**：通过定义清晰的 Service Provider Interface（Metadata、SplitManager、PageSourceProvider、PageSinkProvider），实现数据源的完全可插拔，是查询引擎插件化的教科书级实现。
- **联邦查询的执行计划**：跨数据源 JOIN 的优化（数据源下推、跨源谓词推断）对联邦查询引擎设计有直接参考。
- **管道式执行模型**：数据在算子间以 Page 为单位流水线式传递（无全量中间物化），对低延迟查询引擎的执行模型设计有参考。
- **Dynamic Filtering 实现**：在分布式 JOIN 中，Build 侧完成后向 Probe 侧注入运行时过滤器的机制，对分布式查询优化有重要借鉴。
- **UNNEST 与 Lambda 的类型系统**：在 SQL 类型系统中支持函数类型（Lambda）和集合展开（UNNEST）的设计，对引擎的类型系统扩展有参考。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [trino.sql](../ddl/create-table/trino.sql) |
| 改表 | [trino.sql](../ddl/alter-table/trino.sql) |
| 索引 | [trino.sql](../ddl/indexes/trino.sql) |
| 约束 | [trino.sql](../ddl/constraints/trino.sql) |
| 视图 | [trino.sql](../ddl/views/trino.sql) |
| 序列与自增 | [trino.sql](../ddl/sequences/trino.sql) |
| 数据库/Schema/用户 | [trino.sql](../ddl/users-databases/trino.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [trino.sql](../advanced/dynamic-sql/trino.sql) |
| 错误处理 | [trino.sql](../advanced/error-handling/trino.sql) |
| 执行计划 | [trino.sql](../advanced/explain/trino.sql) |
| 锁机制 | [trino.sql](../advanced/locking/trino.sql) |
| 分区 | [trino.sql](../advanced/partitioning/trino.sql) |
| 权限 | [trino.sql](../advanced/permissions/trino.sql) |
| 存储过程 | [trino.sql](../advanced/stored-procedures/trino.sql) |
| 临时表 | [trino.sql](../advanced/temp-tables/trino.sql) |
| 事务 | [trino.sql](../advanced/transactions/trino.sql) |
| 触发器 | [trino.sql](../advanced/triggers/trino.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [trino.sql](../dml/delete/trino.sql) |
| 插入 | [trino.sql](../dml/insert/trino.sql) |
| 更新 | [trino.sql](../dml/update/trino.sql) |
| Upsert | [trino.sql](../dml/upsert/trino.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [trino.sql](../functions/aggregate/trino.sql) |
| 条件函数 | [trino.sql](../functions/conditional/trino.sql) |
| 日期函数 | [trino.sql](../functions/date-functions/trino.sql) |
| 数学函数 | [trino.sql](../functions/math-functions/trino.sql) |
| 字符串函数 | [trino.sql](../functions/string-functions/trino.sql) |
| 类型转换 | [trino.sql](../functions/type-conversion/trino.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [trino.sql](../query/cte/trino.sql) |
| 全文搜索 | [trino.sql](../query/full-text-search/trino.sql) |
| 连接查询 | [trino.sql](../query/joins/trino.sql) |
| 分页 | [trino.sql](../query/pagination/trino.sql) |
| 行列转换 | [trino.sql](../query/pivot-unpivot/trino.sql) |
| 集合操作 | [trino.sql](../query/set-operations/trino.sql) |
| 子查询 | [trino.sql](../query/subquery/trino.sql) |
| 窗口函数 | [trino.sql](../query/window-functions/trino.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [trino.sql](../scenarios/date-series-fill/trino.sql) |
| 去重 | [trino.sql](../scenarios/deduplication/trino.sql) |
| 区间检测 | [trino.sql](../scenarios/gap-detection/trino.sql) |
| 层级查询 | [trino.sql](../scenarios/hierarchical-query/trino.sql) |
| JSON 展开 | [trino.sql](../scenarios/json-flatten/trino.sql) |
| 迁移速查 | [trino.sql](../scenarios/migration-cheatsheet/trino.sql) |
| TopN 查询 | [trino.sql](../scenarios/ranking-top-n/trino.sql) |
| 累计求和 | [trino.sql](../scenarios/running-total/trino.sql) |
| 缓慢变化维 | [trino.sql](../scenarios/slowly-changing-dim/trino.sql) |
| 字符串拆分 | [trino.sql](../scenarios/string-split-to-rows/trino.sql) |
| 窗口分析 | [trino.sql](../scenarios/window-analytics/trino.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [trino.sql](../types/array-map-struct/trino.sql) |
| 日期时间 | [trino.sql](../types/datetime/trino.sql) |
| JSON | [trino.sql](../types/json/trino.sql) |
| 数值类型 | [trino.sql](../types/numeric/trino.sql) |
| 字符串类型 | [trino.sql](../types/string/trino.sql) |
