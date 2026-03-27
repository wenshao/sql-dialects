# Vertica

**分类**: 列式分析数据库
**文件数**: 51 个 SQL 文件
**总行数**: 4692 行

## 概述与定位

Vertica 是由数据库领域传奇人物 Michael Stonebraker（图灵奖得主）联合创办的列式分析数据库，最初基于其学术项目 C-Store 的研究成果。Vertica 的核心理念是用 Projections（投影）完全替代传统索引：数据以排序后的列存副本形式存储，查询直接扫描最优的 Projection 而无需维护额外索引。现隶属于 OpenText（原 Micro Focus/HP），在电信、金融、广告技术等分析密集型行业有广泛部署。

## 历史与演进

- **2005 年**：Vertica Systems 成立，基于 C-Store 研究项目开发商用列式数据库。
- **2007 年**：Vertica 1.0 发布，以 Projections 为核心的列式存储 + MPP 架构。
- **2011 年**：被 HP 收购，整合到 HP Vertica Analytics Platform 产品线中。
- **2015 年**：引入 Flex Tables（schema-on-read 半结构化数据）、原生支持 Parquet/ORC 外部表。
- **2017 年**：Vertica 9.x 引入 Eon 模式（计算存储分离架构），数据持久化在 S3/HDFS/GCS。
- **2020 年**：增加机器学习库（ML 函数）、改进 Kafka 集成和流式数据摄取。
- **2023 年**：Vertica 23.x 引入 Vertica Accelerator（云全托管服务）、向量搜索、增强 JSON 处理。
- **2024-2025 年**：被 OpenText 收购后继续推进云原生和 AI/ML 集成。

## 核心设计思路

1. **Projections 替代索引**：数据以多个 Projection（排序+列存副本）形式存储，每个 Projection 可有不同的排序键和列组合，优化器自动选择最佳 Projection 响应查询。
2. **SEGMENTED BY**：数据通过 `SEGMENTED BY HASH(col) ALL NODES` 分布到集群各节点，支持 UNSEGMENTED（全复制）策略。
3. **WOS/ROS 架构**：写入先进入 Write Optimized Store（WOS，内存行存），后台 Moveout 将数据转为 Read Optimized Store（ROS，磁盘列存）。
4. **混合负载支持**：通过资源池（Resource Pools）实现 OLTP 级小查询和 OLAP 级大扫描的并发共存。

## 独特特色

| 特性 | 说明 |
|---|---|
| **Projections** | 替代传统索引的核心概念：每个 Projection 是表的一个排序列存副本，可覆盖不同的查询模式，数据库自动维护一致性。 |
| **SEGMENTED BY** | `SEGMENTED BY HASH(col) ALL NODES` 控制数据分片，`UNSEGMENTED ALL NODES` 实现小维表全复制。 |
| **Flex Tables** | Schema-on-read 的半结构化表，`CREATE FLEX TABLE` 后直接加载 JSON/CSV，通过 `MapKeys()` 等函数动态提取列。 |
| **Eon 模式** | 计算存储分离架构，数据存储在 S3/GCS/HDFS，计算节点无状态可弹性伸缩，支持子集群（Subclusters）隔离。 |
| **Tuple Mover** | 后台自动将 WOS 数据合并到 ROS、合并小 ROS 容器，类似 LSM-Tree 的 Compaction 但针对列存优化。 |
| **Database Designer** | 内置自动设计工具，基于查询负载和数据特征自动推荐最优的 Projection 组合。 |
| **原生分析函数** | 丰富的分析函数集（时间序列插值 `TIMESERIES`、模式匹配 `MATCH`、事件会话 `CONDITIONAL_TRUE_EVENT`）。 |

## 已知不足

- **许可成本高**：企业版按节点/TB 计费，成本较高；社区版有 1TB 和 3 节点限制。
- **Projection 管理复杂**：多个 Projection 的存储开销和维护成本随数据量增长显著增加，需要仔细权衡。
- **写入延迟**：虽有 WOS 缓冲，但列存转换（Moveout）过程会消耗资源，不适合高频小事务写入。
- **生态系统较窄**：与主流 BI 工具的集成良好，但 ORM、应用框架和中文社区支持有限。
- **DELETE 性能**：列存表的 DELETE 是逻辑标记删除，实际空间回收需 Mergeout，大规模删除后查询性能可能下降。

## 对引擎开发者的参考价值

- **Projections 模型**：用数据的物理排序副本替代索引的设计思路，彻底消除了索引维护开销和索引-表双重读取的问题，对列存引擎设计有深远影响。
- **WOS/ROS 写入路径**：先行存缓冲再列存持久化的两阶段写入模式，与 LSM-Tree 有异曲同工之处，对实时列存引擎的写入优化有直接参考。
- **Database Designer**：基于查询负载自动推荐物理设计的工具化思路，对自适应物理设计（Adaptive Physical Design）的研究有参考价值。
- **Eon 模式存算分离**：无状态计算节点 + 共享存储 + 子集群隔离的架构，是云原生列存数据库的参考范式。
- **Flex Tables 实现**：在列存引擎中支持 schema-on-read 的做法——通过 __raw__ 列存储原始数据并动态提取——对半结构化数据处理有启发。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [vertica.sql](../ddl/create-table/vertica.sql) |
| 改表 | [vertica.sql](../ddl/alter-table/vertica.sql) |
| 索引 | [vertica.sql](../ddl/indexes/vertica.sql) |
| 约束 | [vertica.sql](../ddl/constraints/vertica.sql) |
| 视图 | [vertica.sql](../ddl/views/vertica.sql) |
| 序列与自增 | [vertica.sql](../ddl/sequences/vertica.sql) |
| 数据库/Schema/用户 | [vertica.sql](../ddl/users-databases/vertica.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [vertica.sql](../advanced/dynamic-sql/vertica.sql) |
| 错误处理 | [vertica.sql](../advanced/error-handling/vertica.sql) |
| 执行计划 | [vertica.sql](../advanced/explain/vertica.sql) |
| 锁机制 | [vertica.sql](../advanced/locking/vertica.sql) |
| 分区 | [vertica.sql](../advanced/partitioning/vertica.sql) |
| 权限 | [vertica.sql](../advanced/permissions/vertica.sql) |
| 存储过程 | [vertica.sql](../advanced/stored-procedures/vertica.sql) |
| 临时表 | [vertica.sql](../advanced/temp-tables/vertica.sql) |
| 事务 | [vertica.sql](../advanced/transactions/vertica.sql) |
| 触发器 | [vertica.sql](../advanced/triggers/vertica.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [vertica.sql](../dml/delete/vertica.sql) |
| 插入 | [vertica.sql](../dml/insert/vertica.sql) |
| 更新 | [vertica.sql](../dml/update/vertica.sql) |
| Upsert | [vertica.sql](../dml/upsert/vertica.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [vertica.sql](../functions/aggregate/vertica.sql) |
| 条件函数 | [vertica.sql](../functions/conditional/vertica.sql) |
| 日期函数 | [vertica.sql](../functions/date-functions/vertica.sql) |
| 数学函数 | [vertica.sql](../functions/math-functions/vertica.sql) |
| 字符串函数 | [vertica.sql](../functions/string-functions/vertica.sql) |
| 类型转换 | [vertica.sql](../functions/type-conversion/vertica.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [vertica.sql](../query/cte/vertica.sql) |
| 全文搜索 | [vertica.sql](../query/full-text-search/vertica.sql) |
| 连接查询 | [vertica.sql](../query/joins/vertica.sql) |
| 分页 | [vertica.sql](../query/pagination/vertica.sql) |
| 行列转换 | [vertica.sql](../query/pivot-unpivot/vertica.sql) |
| 集合操作 | [vertica.sql](../query/set-operations/vertica.sql) |
| 子查询 | [vertica.sql](../query/subquery/vertica.sql) |
| 窗口函数 | [vertica.sql](../query/window-functions/vertica.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [vertica.sql](../scenarios/date-series-fill/vertica.sql) |
| 去重 | [vertica.sql](../scenarios/deduplication/vertica.sql) |
| 区间检测 | [vertica.sql](../scenarios/gap-detection/vertica.sql) |
| 层级查询 | [vertica.sql](../scenarios/hierarchical-query/vertica.sql) |
| JSON 展开 | [vertica.sql](../scenarios/json-flatten/vertica.sql) |
| 迁移速查 | [vertica.sql](../scenarios/migration-cheatsheet/vertica.sql) |
| TopN 查询 | [vertica.sql](../scenarios/ranking-top-n/vertica.sql) |
| 累计求和 | [vertica.sql](../scenarios/running-total/vertica.sql) |
| 缓慢变化维 | [vertica.sql](../scenarios/slowly-changing-dim/vertica.sql) |
| 字符串拆分 | [vertica.sql](../scenarios/string-split-to-rows/vertica.sql) |
| 窗口分析 | [vertica.sql](../scenarios/window-analytics/vertica.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [vertica.sql](../types/array-map-struct/vertica.sql) |
| 日期时间 | [vertica.sql](../types/datetime/vertica.sql) |
| JSON | [vertica.sql](../types/json/vertica.sql) |
| 数值类型 | [vertica.sql](../types/numeric/vertica.sql) |
| 字符串类型 | [vertica.sql](../types/string/vertica.sql) |
