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

| 模块 | 链接 |
|---|---|
| 建表 | [spanner.sql](../ddl/create-table/spanner.sql) |
| 改表 | [spanner.sql](../ddl/alter-table/spanner.sql) |
| 索引 | [spanner.sql](../ddl/indexes/spanner.sql) |
| 约束 | [spanner.sql](../ddl/constraints/spanner.sql) |
| 视图 | [spanner.sql](../ddl/views/spanner.sql) |
| 序列与自增 | [spanner.sql](../ddl/sequences/spanner.sql) |
| 数据库/Schema/用户 | [spanner.sql](../ddl/users-databases/spanner.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [spanner.sql](../advanced/dynamic-sql/spanner.sql) |
| 错误处理 | [spanner.sql](../advanced/error-handling/spanner.sql) |
| 执行计划 | [spanner.sql](../advanced/explain/spanner.sql) |
| 锁机制 | [spanner.sql](../advanced/locking/spanner.sql) |
| 分区 | [spanner.sql](../advanced/partitioning/spanner.sql) |
| 权限 | [spanner.sql](../advanced/permissions/spanner.sql) |
| 存储过程 | [spanner.sql](../advanced/stored-procedures/spanner.sql) |
| 临时表 | [spanner.sql](../advanced/temp-tables/spanner.sql) |
| 事务 | [spanner.sql](../advanced/transactions/spanner.sql) |
| 触发器 | [spanner.sql](../advanced/triggers/spanner.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [spanner.sql](../dml/delete/spanner.sql) |
| 插入 | [spanner.sql](../dml/insert/spanner.sql) |
| 更新 | [spanner.sql](../dml/update/spanner.sql) |
| Upsert | [spanner.sql](../dml/upsert/spanner.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [spanner.sql](../functions/aggregate/spanner.sql) |
| 条件函数 | [spanner.sql](../functions/conditional/spanner.sql) |
| 日期函数 | [spanner.sql](../functions/date-functions/spanner.sql) |
| 数学函数 | [spanner.sql](../functions/math-functions/spanner.sql) |
| 字符串函数 | [spanner.sql](../functions/string-functions/spanner.sql) |
| 类型转换 | [spanner.sql](../functions/type-conversion/spanner.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [spanner.sql](../query/cte/spanner.sql) |
| 全文搜索 | [spanner.sql](../query/full-text-search/spanner.sql) |
| 连接查询 | [spanner.sql](../query/joins/spanner.sql) |
| 分页 | [spanner.sql](../query/pagination/spanner.sql) |
| 行列转换 | [spanner.sql](../query/pivot-unpivot/spanner.sql) |
| 集合操作 | [spanner.sql](../query/set-operations/spanner.sql) |
| 子查询 | [spanner.sql](../query/subquery/spanner.sql) |
| 窗口函数 | [spanner.sql](../query/window-functions/spanner.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [spanner.sql](../scenarios/date-series-fill/spanner.sql) |
| 去重 | [spanner.sql](../scenarios/deduplication/spanner.sql) |
| 区间检测 | [spanner.sql](../scenarios/gap-detection/spanner.sql) |
| 层级查询 | [spanner.sql](../scenarios/hierarchical-query/spanner.sql) |
| JSON 展开 | [spanner.sql](../scenarios/json-flatten/spanner.sql) |
| 迁移速查 | [spanner.sql](../scenarios/migration-cheatsheet/spanner.sql) |
| TopN 查询 | [spanner.sql](../scenarios/ranking-top-n/spanner.sql) |
| 累计求和 | [spanner.sql](../scenarios/running-total/spanner.sql) |
| 缓慢变化维 | [spanner.sql](../scenarios/slowly-changing-dim/spanner.sql) |
| 字符串拆分 | [spanner.sql](../scenarios/string-split-to-rows/spanner.sql) |
| 窗口分析 | [spanner.sql](../scenarios/window-analytics/spanner.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [spanner.sql](../types/array-map-struct/spanner.sql) |
| 日期时间 | [spanner.sql](../types/datetime/spanner.sql) |
| JSON | [spanner.sql](../types/json/spanner.sql) |
| 数值类型 | [spanner.sql](../types/numeric/spanner.sql) |
| 字符串类型 | [spanner.sql](../types/string/spanner.sql) |
