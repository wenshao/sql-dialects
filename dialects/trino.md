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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/trino.sql) | 联邦查询引擎，Connector 对接多数据源，CTAS 常用 |
| [改表](../ddl/alter-table/trino.sql) | ALTER 能力取决于 Connector(Hive/Iceberg/Delta 各不同) |
| [索引](../ddl/indexes/trino.sql) | 无自有索引，依赖底层 Connector 数据源的索引 |
| [约束](../ddl/constraints/trino.sql) | 无约束执行，元数据仅供优化器参考 |
| [视图](../ddl/views/trino.sql) | 视图定义存储在 Connector 中，跨 Catalog 查询 |
| [序列与自增](../ddl/sequences/trino.sql) | 无 SEQUENCE/自增，由底层数据源或 UUID 生成 |
| [数据库/Schema/用户](../ddl/users-databases/trino.sql) | Catalog.Schema.Table 三级命名空间，多数据源联邦 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/trino.sql) | 无动态 SQL/存储过程，纯查询引擎定位 |
| [错误处理](../advanced/error-handling/trino.sql) | 无过程式错误处理，查询级错误返回 |
| [执行计划](../advanced/explain/trino.sql) | EXPLAIN ANALYZE 带分布式 Stage/Fragment 信息 |
| [锁机制](../advanced/locking/trino.sql) | 无锁（查询引擎定位），并发由底层数据源管理 |
| [分区](../advanced/partitioning/trino.sql) | Connector 分区透传(Hive PARTITIONED BY 等) |
| [权限](../advanced/permissions/trino.sql) | 内置 RBAC+Ranger 集成，Catalog/Schema/Table 级 |
| [存储过程](../advanced/stored-procedures/trino.sql) | 无存储过程，纯 SQL 查询引擎 |
| [临时表](../advanced/temp-tables/trino.sql) | 无临时表，用 CTAS+DROP 模拟 |
| [事务](../advanced/transactions/trino.sql) | Connector 级事务(部分)，非完整 ACID |
| [触发器](../advanced/triggers/trino.sql) | 无触发器支持 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/trino.sql) | DELETE 能力取决于 Connector(Hive/Iceberg/Delta) |
| [插入](../dml/insert/trino.sql) | INSERT INTO/CTAS，跨 Connector 数据迁移利器 |
| [更新](../dml/update/trino.sql) | UPDATE 能力取决于 Connector(部分支持) |
| [Upsert](../dml/upsert/trino.sql) | MERGE(Iceberg/Delta Connector)，非通用 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/trino.sql) | GROUPING SETS/CUBE/ROLLUP，approx_distinct HyperLogLog |
| [条件函数](../functions/conditional/trino.sql) | IF/CASE/COALESCE/NULLIF/TRY 标准 |
| [日期函数](../functions/date-functions/trino.sql) | date_trunc/date_add/date_diff，INTERVAL 类型 |
| [数学函数](../functions/math-functions/trino.sql) | 完整数学函数，infinity/nan 处理 |
| [字符串函数](../functions/string-functions/trino.sql) | || 拼接，regexp_extract/replace，split 返回 ARRAY |
| [类型转换](../functions/type-conversion/trino.sql) | CAST+TRY_CAST 安全转换，类型系统严格 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/trino.sql) | WITH 标准+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/trino.sql) | 无内置全文搜索，依赖 Connector(Elasticsearch 等) |
| [连接查询](../query/joins/trino.sql) | Broadcast/Partitioned JOIN，跨 Connector JOIN |
| [分页](../query/pagination/trino.sql) | LIMIT/OFFSET 标准，FETCH FIRST 亦支持 |
| [行列转换](../query/pivot-unpivot/trino.sql) | 无原生 PIVOT，CASE+GROUP BY 模拟 |
| [集合操作](../query/set-operations/trino.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/trino.sql) | 关联子查询+IN/EXISTS，优化器自动去关联 |
| [窗口函数](../query/window-functions/trino.sql) | 完整窗口函数支持，分布式排序 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/trino.sql) | SEQUENCE()+UNNEST 生成日期序列 |
| [去重](../scenarios/deduplication/trino.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/trino.sql) | 窗口函数检测间隙 |
| [层级查询](../scenarios/hierarchical-query/trino.sql) | 递归 CTE 支持 |
| [JSON 展开](../scenarios/json-flatten/trino.sql) | json_extract/json_parse，UNNEST+CAST 展开 JSON 数组 |
| [迁移速查](../scenarios/migration-cheatsheet/trino.sql) | 联邦查询引擎，SQL 方言接近 ANSI，Connector 能力决定 DML |
| [TopN 查询](../scenarios/ranking-top-n/trino.sql) | ROW_NUMBER+窗口函数，LIMIT 直接 TopN |
| [累计求和](../scenarios/running-total/trino.sql) | SUM() OVER 标准，分布式并行 |
| [缓慢变化维](../scenarios/slowly-changing-dim/trino.sql) | MERGE(Iceberg/Delta)，非通用 |
| [字符串拆分](../scenarios/string-split-to-rows/trino.sql) | split()+UNNEST 展开(函数式风格) |
| [窗口分析](../scenarios/window-analytics/trino.sql) | 完整窗口函数，分布式计算 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/trino.sql) | ARRAY/MAP/ROW 原生类型，UNNEST 展开 |
| [日期时间](../types/datetime/trino.sql) | DATE/TIME/TIMESTAMP WITH TZ，INTERVAL 类型 |
| [JSON](../types/json/trino.sql) | JSON 类型，json_extract 路径查询，无 JSON 索引 |
| [数值类型](../types/numeric/trino.sql) | TINYINT-BIGINT/REAL/DOUBLE/DECIMAL(38位)，严格类型 |
| [字符串类型](../types/string/trino.sql) | VARCHAR/CHAR，UTF-8 默认，无 TEXT 别名 |
