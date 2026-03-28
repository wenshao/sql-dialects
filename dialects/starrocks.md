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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/starrocks.md) | MPP 列式(Doris 分叉)，Primary Key/Duplicate/Aggregate/Unique 模型 |
| [改表](../ddl/alter-table/starrocks.md) | Fast Schema Evolution(3.0+) 毫秒级，Light Schema Change |
| [索引](../ddl/indexes/starrocks.md) | Short Key+Bitmap+Bloom Filter+倒排索引，Zone Map 自动 |
| [约束](../ddl/constraints/starrocks.md) | 无传统约束，数据模型替代 |
| [视图](../ddl/views/starrocks.md) | 同步/异步物化视图(2.5+)，自动查询改写 |
| [序列与自增](../ddl/sequences/starrocks.md) | AUTO_INCREMENT(3.0+)，UUID 替代 |
| [数据库/Schema/用户](../ddl/users-databases/starrocks.md) | MySQL 协议兼容，RBAC 权限，Resource Group |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/starrocks.md) | 无存储过程/动态 SQL |
| [错误处理](../advanced/error-handling/starrocks.md) | 无过程式错误处理 |
| [执行计划](../advanced/explain/starrocks.md) | EXPLAIN+ANALYZE 带 Pipeline 执行引擎信息 |
| [锁机制](../advanced/locking/starrocks.md) | 无行级锁，Primary Key 模型 Delete+Insert 语义 |
| [分区](../advanced/partitioning/starrocks.md) | PARTITION BY RANGE+DISTRIBUTED BY HASH，Expression 分区(3.1+) |
| [权限](../advanced/permissions/starrocks.md) | MySQL 兼容权限，RBAC，External Catalog 权限 |
| [存储过程](../advanced/stored-procedures/starrocks.md) | 无存储过程(OLAP 引擎定位) |
| [临时表](../advanced/temp-tables/starrocks.md) | 无临时表 |
| [事务](../advanced/transactions/starrocks.md) | Import 事务原子性，非传统 OLTP 事务 |
| [触发器](../advanced/triggers/starrocks.md) | 无触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/starrocks.md) | DELETE(Primary Key 模型实时删除)，Duplicate 模型不支持 |
| [插入](../dml/insert/starrocks.md) | INSERT INTO+Stream Load/Broker Load/Pipe(3.2+) 持续导入 |
| [更新](../dml/update/starrocks.md) | UPDATE(Primary Key 模型)，Partial Update 部分列更新 |
| [Upsert](../dml/upsert/starrocks.md) | Primary Key 模型天然 Upsert，INSERT INTO 替代 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/starrocks.md) | GROUPING SETS/CUBE/ROLLUP，bitmap_union/hll_union 预聚合 |
| [条件函数](../functions/conditional/starrocks.md) | IF/CASE/COALESCE(MySQL 兼容) |
| [日期函数](../functions/date-functions/starrocks.md) | DATE_FORMAT/DATE_ADD/DATEDIFF(MySQL 兼容) |
| [数学函数](../functions/math-functions/starrocks.md) | 完整数学函数 |
| [字符串函数](../functions/string-functions/starrocks.md) | CONCAT/SUBSTR/REGEXP(MySQL 兼容) |
| [类型转换](../functions/type-conversion/starrocks.md) | CAST 标准(MySQL 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/starrocks.md) | WITH 标准+递归 CTE |
| [全文搜索](../query/full-text-search/starrocks.md) | 倒排索引全文搜索(3.1+)，ngram bloom filter |
| [连接查询](../query/joins/starrocks.md) | Broadcast/Shuffle/Colocate/Bucket JOIN，Runtime Filter 加速 |
| [分页](../query/pagination/starrocks.md) | LIMIT/OFFSET(MySQL 兼容) |
| [行列转换](../query/pivot-unpivot/starrocks.md) | 无原生 PIVOT，CASE+GROUP BY |
| [集合操作](../query/set-operations/starrocks.md) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/starrocks.md) | IN/EXISTS 子查询，关联子查询优化 |
| [窗口函数](../query/window-functions/starrocks.md) | 完整窗口函数，Pipeline 引擎优化 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/starrocks.md) | 无 generate_series，需辅助表 |
| [去重](../scenarios/deduplication/starrocks.md) | Primary Key 模型去重，ROW_NUMBER+CTE |
| [区间检测](../scenarios/gap-detection/starrocks.md) | 窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/starrocks.md) | 递归 CTE 支持 |
| [JSON 展开](../scenarios/json-flatten/starrocks.md) | JSON_EXTRACT+json_each(3.1+)，UNNEST 展开 |
| [迁移速查](../scenarios/migration-cheatsheet/starrocks.md) | MySQL 协议+Doris 分叉，数据模型+物化视图是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/starrocks.md) | ROW_NUMBER+窗口函数，LIMIT 直接 |
| [累计求和](../scenarios/running-total/starrocks.md) | SUM() OVER 标准，Pipeline 引擎加速 |
| [缓慢变化维](../scenarios/slowly-changing-dim/starrocks.md) | Primary Key 模型 Upsert 替代 |
| [字符串拆分](../scenarios/string-split-to-rows/starrocks.md) | UNNEST+SPLIT(3.1+) |
| [窗口分析](../scenarios/window-analytics/starrocks.md) | 完整窗口函数，Pipeline 引擎优化 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/starrocks.md) | ARRAY/MAP/STRUCT(2.5+)，UNNEST+LATERAL JOIN |
| [日期时间](../types/datetime/starrocks.md) | DATE/DATETIME(微秒)，无 TIME/INTERVAL |
| [JSON](../types/json/starrocks.md) | JSON 类型(2.2+)，Flat JSON 自动列化加速 |
| [数值类型](../types/numeric/starrocks.md) | TINYINT-LARGEINT(128位)/FLOAT/DOUBLE/DECIMAL(38) |
| [字符串类型](../types/string/starrocks.md) | VARCHAR(1048576)/CHAR/STRING(3.0+)，UTF-8 |
