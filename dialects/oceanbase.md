# OceanBase

**分类**: 分布式数据库（兼容 MySQL/Oracle）
**文件数**: 51 个 SQL 文件
**总行数**: 4951 行

## 概述与定位

OceanBase 是蚂蚁集团自主研发的分布式关系型数据库，定位于金融级核心系统的在线交易处理（OLTP）场景。它以超大规模、高可用和强一致为核心竞争力，同时提供 MySQL 和 Oracle 双兼容模式，降低传统数据库用户的迁移成本。OceanBase 已在支付宝核心交易系统中经受多年双十一验证，连续刷新 TPC-C 和 TPC-H 基准测试世界纪录。

## 历史与演进

- **2010 年**：蚂蚁金服内部立项，目标替换 Oracle 处理海量支付交易。
- **2014 年**：OceanBase 0.5 上线支付宝核心账务系统。
- **2017 年**：1.x 发布，支持多租户和 MySQL 兼容模式。
- **2019 年**：2.x 引入 Oracle 兼容模式，打破 TPC-C 世界纪录。
- **2021 年**：3.x 开源社区版，引入 HTAP 能力和备份恢复增强。
- **2023 年**：4.x 统一架构（单机分布式一体化），大幅降低小规模部署成本。
- **2024-2025 年**：持续强化多模数据处理、向量检索和 AI 集成。

## 核心设计思路

OceanBase 采用 Shared-Nothing 架构，数据按分区（Partition）分布在多个 OBServer 节点上。每个分区通过 Paxos 协议维护多副本强一致，保证 RPO=0。**多租户**是一等公民概念——同一集群可划分多个 Tenant，每个租户拥有独立的资源配额和兼容模式（MySQL 或 Oracle）。存储层采用 LSM-Tree 结构实现高效写入，基线数据与增量数据分离（Major/Minor Compaction）。事务引擎支持两阶段提交实现跨分区事务。

## 独特特色

- **双模兼容**：同一集群中不同租户可分别运行 MySQL 模式和 Oracle 模式，SQL 语法、数据类型、PL 过程语言各自兼容。
- **Tablegroup**：将频繁 JOIN 的表分区绑定到同一节点，减少分布式事务开销。
- **Primary Zone**：控制 Leader 副本的优先分布区域，优化就近读写。
- **LSM-Tree 存储**：写入性能优异，后台 Compaction 合并，支持数据压缩达到高存储效率。
- **原生多租户**：租户间资源硬隔离（CPU/Memory/IO），单集群可服务数百租户。
- **全局时间戳服务 GTS**：确保跨分区读的全局一致性快照。
- **表级恢复与物理备份**：支持细粒度的 PITR（Point-in-Time Recovery）。

## 已知不足

- Oracle 兼容模式虽覆盖面广，但部分高级 PL/SQL 包和特性仍有差异。
- LSM-Tree 的后台 Compaction 可能导致写放大和周期性 IO 抖动。
- 社区版功能相比企业版有所裁剪（如部分高可用和运维工具）。
- 小规模部署（3 节点以下）相比单机数据库仍有一定运维复杂度，4.x 版本正在改善。
- 生态工具和第三方驱动兼容性不如 MySQL/PostgreSQL 原生生态丰富。
- 分区表数量极多时元数据管理开销增大。

## 对引擎开发者的参考价值

OceanBase 是少数将 Paxos 共识协议工程化落地到金融核心场景的数据库，其多租户资源隔离设计、LSM-Tree 在 OLTP 场景的调优经验、以及双模兼容的 SQL 引擎实现（同一优化器框架适配两套语法体系）对数据库内核开发者极具参考价值。Tablegroup 概念展示了分布式数据库中数据协同放置（co-location）对性能的关键影响。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [oceanbase.sql](../ddl/create-table/oceanbase.sql) |
| 改表 | [oceanbase.sql](../ddl/alter-table/oceanbase.sql) |
| 索引 | [oceanbase.sql](../ddl/indexes/oceanbase.sql) |
| 约束 | [oceanbase.sql](../ddl/constraints/oceanbase.sql) |
| 视图 | [oceanbase.sql](../ddl/views/oceanbase.sql) |
| 序列与自增 | [oceanbase.sql](../ddl/sequences/oceanbase.sql) |
| 数据库/Schema/用户 | [oceanbase.sql](../ddl/users-databases/oceanbase.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [oceanbase.sql](../advanced/dynamic-sql/oceanbase.sql) |
| 错误处理 | [oceanbase.sql](../advanced/error-handling/oceanbase.sql) |
| 执行计划 | [oceanbase.sql](../advanced/explain/oceanbase.sql) |
| 锁机制 | [oceanbase.sql](../advanced/locking/oceanbase.sql) |
| 分区 | [oceanbase.sql](../advanced/partitioning/oceanbase.sql) |
| 权限 | [oceanbase.sql](../advanced/permissions/oceanbase.sql) |
| 存储过程 | [oceanbase.sql](../advanced/stored-procedures/oceanbase.sql) |
| 临时表 | [oceanbase.sql](../advanced/temp-tables/oceanbase.sql) |
| 事务 | [oceanbase.sql](../advanced/transactions/oceanbase.sql) |
| 触发器 | [oceanbase.sql](../advanced/triggers/oceanbase.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [oceanbase.sql](../dml/delete/oceanbase.sql) |
| 插入 | [oceanbase.sql](../dml/insert/oceanbase.sql) |
| 更新 | [oceanbase.sql](../dml/update/oceanbase.sql) |
| Upsert | [oceanbase.sql](../dml/upsert/oceanbase.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [oceanbase.sql](../functions/aggregate/oceanbase.sql) |
| 条件函数 | [oceanbase.sql](../functions/conditional/oceanbase.sql) |
| 日期函数 | [oceanbase.sql](../functions/date-functions/oceanbase.sql) |
| 数学函数 | [oceanbase.sql](../functions/math-functions/oceanbase.sql) |
| 字符串函数 | [oceanbase.sql](../functions/string-functions/oceanbase.sql) |
| 类型转换 | [oceanbase.sql](../functions/type-conversion/oceanbase.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [oceanbase.sql](../query/cte/oceanbase.sql) |
| 全文搜索 | [oceanbase.sql](../query/full-text-search/oceanbase.sql) |
| 连接查询 | [oceanbase.sql](../query/joins/oceanbase.sql) |
| 分页 | [oceanbase.sql](../query/pagination/oceanbase.sql) |
| 行列转换 | [oceanbase.sql](../query/pivot-unpivot/oceanbase.sql) |
| 集合操作 | [oceanbase.sql](../query/set-operations/oceanbase.sql) |
| 子查询 | [oceanbase.sql](../query/subquery/oceanbase.sql) |
| 窗口函数 | [oceanbase.sql](../query/window-functions/oceanbase.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [oceanbase.sql](../scenarios/date-series-fill/oceanbase.sql) |
| 去重 | [oceanbase.sql](../scenarios/deduplication/oceanbase.sql) |
| 区间检测 | [oceanbase.sql](../scenarios/gap-detection/oceanbase.sql) |
| 层级查询 | [oceanbase.sql](../scenarios/hierarchical-query/oceanbase.sql) |
| JSON 展开 | [oceanbase.sql](../scenarios/json-flatten/oceanbase.sql) |
| 迁移速查 | [oceanbase.sql](../scenarios/migration-cheatsheet/oceanbase.sql) |
| TopN 查询 | [oceanbase.sql](../scenarios/ranking-top-n/oceanbase.sql) |
| 累计求和 | [oceanbase.sql](../scenarios/running-total/oceanbase.sql) |
| 缓慢变化维 | [oceanbase.sql](../scenarios/slowly-changing-dim/oceanbase.sql) |
| 字符串拆分 | [oceanbase.sql](../scenarios/string-split-to-rows/oceanbase.sql) |
| 窗口分析 | [oceanbase.sql](../scenarios/window-analytics/oceanbase.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [oceanbase.sql](../types/array-map-struct/oceanbase.sql) |
| 日期时间 | [oceanbase.sql](../types/datetime/oceanbase.sql) |
| JSON | [oceanbase.sql](../types/json/oceanbase.sql) |
| 数值类型 | [oceanbase.sql](../types/numeric/oceanbase.sql) |
| 字符串类型 | [oceanbase.sql](../types/string/oceanbase.sql) |
