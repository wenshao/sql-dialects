# Google Cloud Spanner

**分类**: 全球分布式数据库（Google）
**文件数**: 51 个 SQL 文件
**总行数**: 5017 行

## 概述与定位

Google Cloud Spanner 是 Google 开发的全球分布式关系型数据库，也是业界首个实现外部一致性（external consistency）的商用系统。Spanner 定位于需要全球多区域部署、强一致事务和极高可用性的关键业务场景，如金融交易、全球用户系统和游戏后端。它提供关系模型和 SQL 查询能力，同时保持近乎无限的水平扩展。

## 历史与演进

- **2007 年**：Google 内部开始 Spanner 项目，目标替代 Bigtable 在需要事务场景的不足。
- **2012 年**：发表具有里程碑意义的 Spanner 论文，首次公开 TrueTime 机制。
- **2013 年**：发表 F1 论文，展示 Spanner 如何承载 Google AdWords 核心业务。
- **2017 年**：Cloud Spanner GA，作为全托管服务对外开放。
- **2019 年**：引入 GoogleSQL 方言增强和查询优化器改进。
- **2022 年**：推出 PostgreSQL 接口模式，提供 PG 兼容的连接方式。
- **2023-2025 年**：支持自动缩容、更灵活的实例配置、向量搜索和 AI 集成。

## 核心设计思路

Spanner 最核心的创新是 **TrueTime**——通过 GPS 时钟和原子钟提供全球一致的时间参考，使分布式事务无需额外通信即可获得外部一致性。数据以 Split 为单位分布，每个 Split 通过 Paxos 协议跨区域复制。Schema 设计高度强调**父子表交错**（INTERLEAVE IN PARENT），将相关数据物理共置以减少分布式 JOIN 开销。**不支持自增主键**是一个刻意的设计决策——要求用户使用 UUID 或复合主键避免写热点。

## 独特特色

- **TrueTime 与外部一致性**：提供比 SERIALIZABLE 更强的一致性保证——事务的提交顺序与真实时间一致。
- **INTERLEAVE IN PARENT**：`CREATE TABLE Orders (...) INTERLEAVE IN PARENT Customers ON DELETE CASCADE` 将子表数据与父表物理交错存储。
- **无自增主键**：刻意不支持 AUTO_INCREMENT/SERIAL，强制使用 UUID 或应用生成的分散 ID。
- **GoogleSQL 方言**：在标准 SQL 基础上提供 STRUCT、ARRAY 等丰富类型和函数。
- **Stale Read**：`SELECT ... WITH (EXACT_STALENESS = '10s')` 允许读取略旧的快照以降低延迟。
- **变更流 (Change Streams)**：追踪数据变更用于下游消费。
- **多区域配置**：支持区域级、双区域和多区域实例配置，SLA 最高达 99.999%。

## 已知不足

- **仅限 Google Cloud**：无法在其他云或本地私有化部署（模拟器仅用于开发测试）。
- 不支持自增主键，对习惯 AUTO_INCREMENT 的开发者有较大学习成本。
- 无存储过程和触发器，服务端逻辑需在应用层实现。
- 强一致跨区域写入的延迟受物理距离限制（通常数百毫秒）。
- DDL 操作是长时运行任务，无法在事务中执行。
- 成本相对较高，按节点小时和存储容量计费。
- PostgreSQL 接口模式的兼容性有限，许多 PG 特性不支持。

## 对引擎开发者的参考价值

Spanner 的 TrueTime 机制是分布式系统时钟理论的工程化突破，展示了硬件时钟如何解决分布式因果序问题。INTERLEAVE IN PARENT 的数据共置策略对所有分布式数据库的 Schema 设计都有深刻启示。其论文对分布式事务、半同步复制和全球一致性的讨论是数据库领域的经典参考。不支持自增主键的设计哲学体现了分布式场景下的范式转变。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/spanner.sql) | 全球分布式，INTERLEAVE IN 父子表共置(独有)，强一致性 |
| [改表](../ddl/alter-table/spanner.sql) | 在线 Schema 变更(长时间运行)，分布式原子 DDL |
| [索引](../ddl/indexes/spanner.sql) | 分布式二级索引，STORING 覆盖列，INTERLEAVE 共置索引 |
| [约束](../ddl/constraints/spanner.sql) | PK/FK/CHECK/UNIQUE 完整，分布式强一致约束 |
| [视图](../ddl/views/spanner.sql) | 普通视图支持，无物化视图 |
| [序列与自增](../ddl/sequences/spanner.sql) | 无 AUTO_INCREMENT，UUID 或 bit-reversed SEQUENCE(2023+) |
| [数据库/Schema/用户](../ddl/users-databases/spanner.sql) | Instance→Database→Schema，IAM 权限，全球部署 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/spanner.sql) | 无动态 SQL，客户端 SDK 构建查询 |
| [错误处理](../advanced/error-handling/spanner.sql) | 无过程式错误处理，gRPC 错误码 |
| [执行计划](../advanced/explain/spanner.sql) | EXPLAIN 分布式执行计划，Query Statistics |
| [锁机制](../advanced/locking/spanner.sql) | TrueTime+2PL(Paxos)，外部一致性(最强一致性) |
| [分区](../advanced/partitioning/spanner.sql) | Split 自动分片(基于负载)，无手动分区 |
| [权限](../advanced/permissions/spanner.sql) | IAM+Fine-Grained Access Control(FGAC)，列级权限 |
| [存储过程](../advanced/stored-procedures/spanner.sql) | 无存储过程，逻辑在应用层 |
| [临时表](../advanced/temp-tables/spanner.sql) | 无临时表支持 |
| [事务](../advanced/transactions/spanner.sql) | TrueTime 外部一致性(全球最强)，读写/只读事务 |
| [触发器](../advanced/triggers/spanner.sql) | 无触发器，Change Streams 替代 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/spanner.sql) | DELETE+WHERE 标准，分布式并行 |
| [插入](../dml/insert/spanner.sql) | INSERT/INSERT OR UPDATE，Mutation API 批量写入 |
| [更新](../dml/update/spanner.sql) | UPDATE 标准，分布式事务 |
| [Upsert](../dml/upsert/spanner.sql) | INSERT OR UPDATE(原生 Upsert)，非标准 MERGE |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/spanner.sql) | 标准聚合函数，ARRAY_AGG，分布式并行聚合 |
| [条件函数](../functions/conditional/spanner.sql) | IF/CASE/COALESCE/IFNULL，GoogleSQL 方言 |
| [日期函数](../functions/date-functions/spanner.sql) | DATE_TRUNC/DATE_ADD/DATE_DIFF/EXTRACT(GoogleSQL) |
| [数学函数](../functions/math-functions/spanner.sql) | 完整数学函数(GoogleSQL) |
| [字符串函数](../functions/string-functions/spanner.sql) | CONCAT/SUBSTR/REGEXP_EXTRACT(GoogleSQL 同 BigQuery) |
| [类型转换](../functions/type-conversion/spanner.sql) | CAST/SAFE_CAST(同 BigQuery)，严格类型 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/spanner.sql) | WITH 标准+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/spanner.sql) | SEARCH INDEX+TOKENIZE 全文搜索(2023+) |
| [连接查询](../query/joins/spanner.sql) | 分布式 JOIN，INTERLEAVE 共置优化，HASH JOIN |
| [分页](../query/pagination/spanner.sql) | LIMIT/OFFSET 标准，Keyset 分页推荐 |
| [行列转换](../query/pivot-unpivot/spanner.sql) | 无原生 PIVOT |
| [集合操作](../query/set-operations/spanner.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/spanner.sql) | 关联子查询+IN/EXISTS(GoogleSQL) |
| [窗口函数](../query/window-functions/spanner.sql) | 完整窗口函数(GoogleSQL)，QUALIFY 支持 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/spanner.sql) | GENERATE_DATE_ARRAY+UNNEST(同 BigQuery) |
| [去重](../scenarios/deduplication/spanner.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/spanner.sql) | GENERATE_DATE_ARRAY+窗口函数 |
| [层级查询](../scenarios/hierarchical-query/spanner.sql) | 递归 CTE 支持 |
| [JSON 展开](../scenarios/json-flatten/spanner.sql) | JSON_EXTRACT/JSON_QUERY+UNNEST 展开 |
| [迁移速查](../scenarios/migration-cheatsheet/spanner.sql) | INTERLEAVE 共置+TrueTime+GoogleSQL 方言是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/spanner.sql) | ROW_NUMBER+LIMIT 标准 |
| [累计求和](../scenarios/running-total/spanner.sql) | SUM() OVER 标准，分布式并行 |
| [缓慢变化维](../scenarios/slowly-changing-dim/spanner.sql) | INSERT OR UPDATE+事务，无 MERGE |
| [字符串拆分](../scenarios/string-split-to-rows/spanner.sql) | SPLIT+UNNEST 展开(同 BigQuery) |
| [窗口分析](../scenarios/window-analytics/spanner.sql) | 完整窗口函数(GoogleSQL)，QUALIFY 支持 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/spanner.sql) | ARRAY/STRUCT 支持(同 BigQuery)，INTERLEAVE 父子表 |
| [日期时间](../types/datetime/spanner.sql) | DATE/TIMESTAMP(UTC 强制)，无 TIME/INTERVAL |
| [JSON](../types/json/spanner.sql) | JSON 类型(2022+)，JSON_EXTRACT 路径查询 |
| [数值类型](../types/numeric/spanner.sql) | INT64/FLOAT32/FLOAT64/NUMERIC/BOOL(GoogleSQL) |
| [字符串类型](../types/string/spanner.sql) | STRING 无长度限制，BYTES 二进制(同 BigQuery) |
