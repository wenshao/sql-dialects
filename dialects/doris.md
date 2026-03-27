# Apache Doris

**分类**: MPP 分析数据库（Apache）
**文件数**: 51 个 SQL 文件
**总行数**: 4391 行

## 概述与定位

Apache Doris 是一款开源的 MPP 分析数据库，源自百度内部的 Palo 项目，2018 年捐赠给 Apache 基金会。Doris 定位于实时分析场景——亚秒级查询响应、高并发低延迟的 OLAP 查询，兼顾批量数据导入和实时数据摄取。它与 StarRocks 同源（StarRocks 是 2020 年从 Doris 分叉），二者在架构和 SQL 方言上有大量相似之处。Doris 在中国互联网、金融、电信行业有广泛应用。

## 历史与演进

- **2012 年**：百度内部启动 Palo 项目，面向广告报表等实时分析场景。
- **2018 年**：Palo 捐赠给 Apache 基金会，更名为 Apache Doris（孵化器项目）。
- **2020 年**：StarRocks（原 DorisDB）从 Doris 分叉，开始独立发展。
- **2022 年**：Apache Doris 毕业成为顶级项目，1.x 版本引入向量化执行引擎、Bitmap 索引增强。
- **2023 年**：Doris 2.0 引入倒排索引、存算分离架构（预览）、Merge-on-Write 优化 Unique 模型。
- **2024-2025 年**：增强存算分离（Cloud-Native）、自动物化视图、多目录联邦查询（Multi-Catalog）、半结构化数据变体类型（Variant）。

## 核心设计思路

1. **FE + BE 架构**：Frontend（FE）负责 SQL 解析、优化和元数据管理，Backend（BE）负责数据存储和查询执行，二者均可水平扩展。
2. **四种数据模型**：Duplicate（明细）、Aggregate（预聚合）、Unique（唯一键去重）、Primary Key（主键实时更新），根据业务场景选择。
3. **MPP 向量化执行**：基于列式内存布局的向量化执行引擎，配合 Pipeline 执行模型，充分利用 CPU 缓存和 SIMD 指令。
4. **MySQL 协议兼容**：使用 MySQL 客户端/驱动即可连接 Doris，降低了迁移和接入成本。

## 独特特色

| 特性 | 说明 |
|---|---|
| **四种数据模型** | Duplicate（全量明细）、Aggregate（写入时预聚合）、Unique（唯一键最新值）——根据查询模式选择最优模型。 |
| **ROLLUP** | 在基础表上创建 ROLLUP 物化索引，预计算特定维度组合的聚合结果，优化器自动命中最优 ROLLUP。 |
| **物化视图** | 支持同步和异步物化视图，优化器可透明路由查询到物化视图，加速聚合类查询。 |
| **Multi-Catalog** | 通过 Catalog 机制直接查询 Hive/Iceberg/Hudi/Elasticsearch/MySQL/PostgreSQL 等外部数据源，无需 ETL。 |
| **Stream Load** | 通过 HTTP PUT 接口实时推送 JSON/CSV 数据到 Doris，支持事务性写入和 exactly-once 语义。 |
| **Light Schema Change** | 列的增删改可在秒级完成，无需数据重写，对在线业务友好。 |
| **Runtime Filter** | 运行时动态生成 Bloom Filter / IN 谓词下推到扫描侧，减少 JOIN 的数据量，对星型模型查询效果显著。 |

## 已知不足

- **事务能力有限**：不支持标准的 BEGIN/COMMIT/ROLLBACK 多语句事务，每个导入任务是一个原子操作。
- **存储过程/触发器缺失**：不支持传统 RDBMS 的存储过程、触发器和游标，过程化逻辑需在应用层实现。
- **UPDATE/DELETE 限制**：仅 Unique/Primary Key 模型支持行级更新和删除，Aggregate/Duplicate 模型不支持。
- **单表数据规模**：虽然支持分区和分桶，但单表超过数百亿行时性能调优难度增加。
- **与 StarRocks 的差异化**：二者功能高度重合，社区和用户在选型时容易产生困惑。

## 对引擎开发者的参考价值

- **多数据模型设计**：在建表时选择 Duplicate/Aggregate/Unique 模型的设计，将查询优化前置到 DDL 阶段，对分析引擎的数据建模有启发。
- **ROLLUP 自动路由**：优化器根据查询的维度和度量自动选择最优 ROLLUP 的实现，对物化视图匹配算法有参考。
- **Runtime Filter 实现**：在 Hash Join 的 Build 侧动态生成 Filter 并下推到 Probe 侧扫描的机制，是分布式 JOIN 优化的实用技术。
- **FE/BE 分离架构**：元数据和计算的解耦设计（FE 管理 + BE 执行），对分布式数据库的架构分层有参考。
- **Light Schema Change**：列元数据变更不触发数据重写的实现（仅修改 FE 元数据 + BE 文件 Footer），对在线 DDL 设计有借鉴。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [doris.sql](../ddl/create-table/doris.sql) |
| 改表 | [doris.sql](../ddl/alter-table/doris.sql) |
| 索引 | [doris.sql](../ddl/indexes/doris.sql) |
| 约束 | [doris.sql](../ddl/constraints/doris.sql) |
| 视图 | [doris.sql](../ddl/views/doris.sql) |
| 序列与自增 | [doris.sql](../ddl/sequences/doris.sql) |
| 数据库/Schema/用户 | [doris.sql](../ddl/users-databases/doris.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [doris.sql](../advanced/dynamic-sql/doris.sql) |
| 错误处理 | [doris.sql](../advanced/error-handling/doris.sql) |
| 执行计划 | [doris.sql](../advanced/explain/doris.sql) |
| 锁机制 | [doris.sql](../advanced/locking/doris.sql) |
| 分区 | [doris.sql](../advanced/partitioning/doris.sql) |
| 权限 | [doris.sql](../advanced/permissions/doris.sql) |
| 存储过程 | [doris.sql](../advanced/stored-procedures/doris.sql) |
| 临时表 | [doris.sql](../advanced/temp-tables/doris.sql) |
| 事务 | [doris.sql](../advanced/transactions/doris.sql) |
| 触发器 | [doris.sql](../advanced/triggers/doris.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [doris.sql](../dml/delete/doris.sql) |
| 插入 | [doris.sql](../dml/insert/doris.sql) |
| 更新 | [doris.sql](../dml/update/doris.sql) |
| Upsert | [doris.sql](../dml/upsert/doris.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [doris.sql](../functions/aggregate/doris.sql) |
| 条件函数 | [doris.sql](../functions/conditional/doris.sql) |
| 日期函数 | [doris.sql](../functions/date-functions/doris.sql) |
| 数学函数 | [doris.sql](../functions/math-functions/doris.sql) |
| 字符串函数 | [doris.sql](../functions/string-functions/doris.sql) |
| 类型转换 | [doris.sql](../functions/type-conversion/doris.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [doris.sql](../query/cte/doris.sql) |
| 全文搜索 | [doris.sql](../query/full-text-search/doris.sql) |
| 连接查询 | [doris.sql](../query/joins/doris.sql) |
| 分页 | [doris.sql](../query/pagination/doris.sql) |
| 行列转换 | [doris.sql](../query/pivot-unpivot/doris.sql) |
| 集合操作 | [doris.sql](../query/set-operations/doris.sql) |
| 子查询 | [doris.sql](../query/subquery/doris.sql) |
| 窗口函数 | [doris.sql](../query/window-functions/doris.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [doris.sql](../scenarios/date-series-fill/doris.sql) |
| 去重 | [doris.sql](../scenarios/deduplication/doris.sql) |
| 区间检测 | [doris.sql](../scenarios/gap-detection/doris.sql) |
| 层级查询 | [doris.sql](../scenarios/hierarchical-query/doris.sql) |
| JSON 展开 | [doris.sql](../scenarios/json-flatten/doris.sql) |
| 迁移速查 | [doris.sql](../scenarios/migration-cheatsheet/doris.sql) |
| TopN 查询 | [doris.sql](../scenarios/ranking-top-n/doris.sql) |
| 累计求和 | [doris.sql](../scenarios/running-total/doris.sql) |
| 缓慢变化维 | [doris.sql](../scenarios/slowly-changing-dim/doris.sql) |
| 字符串拆分 | [doris.sql](../scenarios/string-split-to-rows/doris.sql) |
| 窗口分析 | [doris.sql](../scenarios/window-analytics/doris.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [doris.sql](../types/array-map-struct/doris.sql) |
| 日期时间 | [doris.sql](../types/datetime/doris.sql) |
| JSON | [doris.sql](../types/json/doris.sql) |
| 数值类型 | [doris.sql](../types/numeric/doris.sql) |
| 字符串类型 | [doris.sql](../types/string/doris.sql) |
