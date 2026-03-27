# TiDB

**分类**: 分布式数据库（兼容 MySQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4374 行

## 概述与定位

TiDB 是 PingCAP 于 2015 年开源的分布式关系型数据库，目标是在一套系统中同时满足 OLTP 与 OLAP 工作负载（HTAP）。它在 SQL 层高度兼容 MySQL 协议与语法，使现有 MySQL 应用可以低成本迁移；在存储层则采用分布式 KV 引擎 TiKV 和列存引擎 TiFlash 实现水平扩展与实时分析。TiDB 定位于需要弹性伸缩、强一致事务和实时分析的互联网与金融场景。

## 历史与演进

- **2015 年**：PingCAP 成立并启动 TiDB 项目，受 Google Spanner/F1 论文启发。
- **2017 年**：TiDB 1.0 GA，基本实现 MySQL 兼容与分布式事务。
- **2019 年**：3.0 引入 TiFlash 列存引擎，正式支持 HTAP 场景。
- **2020 年**：4.0 推出 TiDB Dashboard、Placement Rules、BR 备份恢复。
- **2021 年**：5.0 引入 MPP 计算框架，TiFlash 可独立承担分析查询。
- **2022 年**：6.0 引入 Placement Rules in SQL、热点小表缓存、Top SQL。
- **2023-2024 年**：7.x 持续增强资源管控（Resource Control）、全局排序、TiDB Serverless。
- **2025 年**：8.x 强化多租户隔离、向量搜索和 AI 集成能力。

## 核心设计思路

TiDB 采用计算与存储分离的分层架构：**TiDB Server** 负责 SQL 解析和优化（无状态，可水平扩展）；**TiKV** 以 Region 为单位管理数据、通过 Multi-Raft 协议实现强一致复制；**PD (Placement Driver)** 负责元数据管理和调度。事务模型基于 Percolator（乐观/悲观两种模式），提供 Snapshot Isolation 默认隔离级别。TiFlash 作为列存副本通过 Raft Learner 实时同步数据，查询优化器可自动选择行存或列存路径。

## 独特特色

- **AUTO_RANDOM**：用随机位替代自增 ID 的高位，避免写热点集中在单一 Region。
- **TiFlash 列存引擎**：通过 `ALTER TABLE t SET TIFLASH REPLICA 1` 即可为任意表创建列存副本，优化器自动路由分析查询。
- **MPP 框架**：TiFlash 节点之间可协作完成分布式 Join 和聚合，无需额外 OLAP 引擎。
- **Placement Rules in SQL**：用 `ALTER TABLE ... PLACEMENT POLICY` 控制数据的地域分布与副本策略。
- **资源管控**：通过 Resource Control 实现多租户间 CPU/IO 配额管理。
- **AUTO_ID_CACHE**：控制自增 ID 缓存粒度，在分布式场景下平衡性能与连续性。
- **TTL 表**：支持行级 TTL，到期数据自动清理。

## 已知不足

- 与 MySQL 的兼容性仍有差异：不支持存储过程（仅实验性）、外键约束为实验特性、触发器不支持。
- 自增 ID 不保证全局连续，跨 TiDB 实例可能出现间隙和乱序。
- 全文索引不支持（需借助外部搜索引擎）。
- 单行大事务有大小限制（默认 6 MB TxnTotalSizeLimit）。
- 部分 MySQL 内置函数和系统变量尚未实现。
- TiFlash 同步存在短暂延迟，对实时性要求极高的分析场景需注意。

## 对引擎开发者的参考价值

TiDB 的架构设计为 SQL 引擎开发提供了重要参考：Raft 共识在数据库中的工程实现（Multi-Raft 分裂/合并/调度）、Percolator 分布式事务模型的生产化改进（悲观锁扩展）、行列混存的 HTAP 路由决策、以及计算层无状态设计对弹性伸缩的支撑。AUTO_RANDOM 的热点打散思路和 Placement Rules 的数据放置抽象对分布式系统设计有普遍借鉴意义。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [tidb.sql](../ddl/create-table/tidb.sql) |
| 改表 | [tidb.sql](../ddl/alter-table/tidb.sql) |
| 索引 | [tidb.sql](../ddl/indexes/tidb.sql) |
| 约束 | [tidb.sql](../ddl/constraints/tidb.sql) |
| 视图 | [tidb.sql](../ddl/views/tidb.sql) |
| 序列与自增 | [tidb.sql](../ddl/sequences/tidb.sql) |
| 数据库/Schema/用户 | [tidb.sql](../ddl/users-databases/tidb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [tidb.sql](../advanced/dynamic-sql/tidb.sql) |
| 错误处理 | [tidb.sql](../advanced/error-handling/tidb.sql) |
| 执行计划 | [tidb.sql](../advanced/explain/tidb.sql) |
| 锁机制 | [tidb.sql](../advanced/locking/tidb.sql) |
| 分区 | [tidb.sql](../advanced/partitioning/tidb.sql) |
| 权限 | [tidb.sql](../advanced/permissions/tidb.sql) |
| 存储过程 | [tidb.sql](../advanced/stored-procedures/tidb.sql) |
| 临时表 | [tidb.sql](../advanced/temp-tables/tidb.sql) |
| 事务 | [tidb.sql](../advanced/transactions/tidb.sql) |
| 触发器 | [tidb.sql](../advanced/triggers/tidb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [tidb.sql](../dml/delete/tidb.sql) |
| 插入 | [tidb.sql](../dml/insert/tidb.sql) |
| 更新 | [tidb.sql](../dml/update/tidb.sql) |
| Upsert | [tidb.sql](../dml/upsert/tidb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [tidb.sql](../functions/aggregate/tidb.sql) |
| 条件函数 | [tidb.sql](../functions/conditional/tidb.sql) |
| 日期函数 | [tidb.sql](../functions/date-functions/tidb.sql) |
| 数学函数 | [tidb.sql](../functions/math-functions/tidb.sql) |
| 字符串函数 | [tidb.sql](../functions/string-functions/tidb.sql) |
| 类型转换 | [tidb.sql](../functions/type-conversion/tidb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [tidb.sql](../query/cte/tidb.sql) |
| 全文搜索 | [tidb.sql](../query/full-text-search/tidb.sql) |
| 连接查询 | [tidb.sql](../query/joins/tidb.sql) |
| 分页 | [tidb.sql](../query/pagination/tidb.sql) |
| 行列转换 | [tidb.sql](../query/pivot-unpivot/tidb.sql) |
| 集合操作 | [tidb.sql](../query/set-operations/tidb.sql) |
| 子查询 | [tidb.sql](../query/subquery/tidb.sql) |
| 窗口函数 | [tidb.sql](../query/window-functions/tidb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [tidb.sql](../scenarios/date-series-fill/tidb.sql) |
| 去重 | [tidb.sql](../scenarios/deduplication/tidb.sql) |
| 区间检测 | [tidb.sql](../scenarios/gap-detection/tidb.sql) |
| 层级查询 | [tidb.sql](../scenarios/hierarchical-query/tidb.sql) |
| JSON 展开 | [tidb.sql](../scenarios/json-flatten/tidb.sql) |
| 迁移速查 | [tidb.sql](../scenarios/migration-cheatsheet/tidb.sql) |
| TopN 查询 | [tidb.sql](../scenarios/ranking-top-n/tidb.sql) |
| 累计求和 | [tidb.sql](../scenarios/running-total/tidb.sql) |
| 缓慢变化维 | [tidb.sql](../scenarios/slowly-changing-dim/tidb.sql) |
| 字符串拆分 | [tidb.sql](../scenarios/string-split-to-rows/tidb.sql) |
| 窗口分析 | [tidb.sql](../scenarios/window-analytics/tidb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [tidb.sql](../types/array-map-struct/tidb.sql) |
| 日期时间 | [tidb.sql](../types/datetime/tidb.sql) |
| JSON | [tidb.sql](../types/json/tidb.sql) |
| 数值类型 | [tidb.sql](../types/numeric/tidb.sql) |
| 字符串类型 | [tidb.sql](../types/string/tidb.sql) |
