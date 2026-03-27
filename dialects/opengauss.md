# openGauss

**分类**: 开源数据库（华为，基于 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4877 行

## 概述与定位

openGauss 是华为于 2020 年开源的关系型数据库，源自华为内部的 GaussDB 产品，基于 PostgreSQL 9.2 内核深度改造。openGauss 定位于企业级核心交易系统，特别强调高性能、高可用和安全合规。它针对华为鲲鹏（ARM）处理器做了深度优化，同时也支持 x86 架构，是中国信创生态的重要数据库选项。

## 历史与演进

- **2011 年**：华为内部启动 GaussDB 项目，基于 PostgreSQL 内核开发。
- **2019 年**：GaussDB 作为华为云服务商用，积累金融和政企客户。
- **2020 年 6 月**：以 openGauss 品牌正式开源，采用木兰宽松许可证。
- **2021 年**：openGauss 2.0 引入内存表（MOT）引擎和 AI4DB 能力。
- **2022 年**：3.0 推出 Sharding 分布式方案和数据库运维 AI 工具。
- **2023 年**：5.0 引入分布式强一致事务和列存引擎增强。
- **2024-2025 年**：持续完善生态工具链和多模数据支持。

## 核心设计思路

openGauss 在 PostgreSQL 内核基础上做了大量底层改造：线程化架构（替代 PG 的多进程模型，减少上下文切换开销）、NUMA-Aware 内存分配（针对多路服务器优化）、以及增量检查点机制。存储引擎支持行存（Astore/Ustore）和列存（CStore），Ustore 采用 Undo Log 实现就地更新，减少存储膨胀。安全方面内置全密态数据库能力和透明数据加密。

## 独特特色

- **MOT (Memory-Optimized Table)**：内存优化表引擎，采用乐观并发控制和 Lock-Free 索引，极端 OLTP 场景下可达数百万 TPS。
- **AI4DB**：内置 AI 调优能力——自动索引推荐、慢 SQL 诊断、负载预测和参数自调优。
- **鲲鹏优化**：针对 ARM 架构的 SIMD 指令、原子操作和缓存行优化。
- **Ustore 引擎**：基于 Undo Log 的就地更新存储引擎，解决 PG 原生 MVCC 的 Bloat 问题。
- **全密态计算**：数据在计算过程中保持加密状态，防止 DBA 窥探敏感数据。
- **DB4AI**：数据库内置机器学习算法，支持 `CREATE MODEL` 语法直接在库内训练模型。
- **WDR 报告**：Workload Diagnosis Report 类似 Oracle AWR，提供全面的性能诊断。

## 已知不足

- 基于 PG 9.2 内核分叉较早，缺少 PG 后续版本的大量新特性（如逻辑复制增强、JIT 编译等）。
- 与最新 PostgreSQL 的兼容性存在差距，部分 PG 扩展不能直接使用。
- 社区规模相比 PostgreSQL/MySQL 较小，第三方工具和文档资源有限。
- MOT 内存表不支持所有 SQL 特性（如部分 DDL 操作和复杂约束）。
- 线程模型虽提升了短连接性能，但在超高并发场景下线程调度也有瓶颈。
- 国际社区参与度有限，文档和社区交流以中文为主。

## 对引擎开发者的参考价值

openGauss 展示了如何在 PostgreSQL 基础上进行深度内核改造：从多进程到多线程架构的迁移经验、NUMA-Aware 内存管理的实践、Ustore 引擎对 MVCC Bloat 问题的解决方案、以及 MOT 内存引擎的 Lock-Free 并发控制设计。其 AI4DB 集成（将机器学习嵌入数据库调优流程）代表了数据库自治化的一个方向。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [opengauss.sql](../ddl/create-table/opengauss.sql) |
| 改表 | [opengauss.sql](../ddl/alter-table/opengauss.sql) |
| 索引 | [opengauss.sql](../ddl/indexes/opengauss.sql) |
| 约束 | [opengauss.sql](../ddl/constraints/opengauss.sql) |
| 视图 | [opengauss.sql](../ddl/views/opengauss.sql) |
| 序列与自增 | [opengauss.sql](../ddl/sequences/opengauss.sql) |
| 数据库/Schema/用户 | [opengauss.sql](../ddl/users-databases/opengauss.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [opengauss.sql](../advanced/dynamic-sql/opengauss.sql) |
| 错误处理 | [opengauss.sql](../advanced/error-handling/opengauss.sql) |
| 执行计划 | [opengauss.sql](../advanced/explain/opengauss.sql) |
| 锁机制 | [opengauss.sql](../advanced/locking/opengauss.sql) |
| 分区 | [opengauss.sql](../advanced/partitioning/opengauss.sql) |
| 权限 | [opengauss.sql](../advanced/permissions/opengauss.sql) |
| 存储过程 | [opengauss.sql](../advanced/stored-procedures/opengauss.sql) |
| 临时表 | [opengauss.sql](../advanced/temp-tables/opengauss.sql) |
| 事务 | [opengauss.sql](../advanced/transactions/opengauss.sql) |
| 触发器 | [opengauss.sql](../advanced/triggers/opengauss.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [opengauss.sql](../dml/delete/opengauss.sql) |
| 插入 | [opengauss.sql](../dml/insert/opengauss.sql) |
| 更新 | [opengauss.sql](../dml/update/opengauss.sql) |
| Upsert | [opengauss.sql](../dml/upsert/opengauss.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [opengauss.sql](../functions/aggregate/opengauss.sql) |
| 条件函数 | [opengauss.sql](../functions/conditional/opengauss.sql) |
| 日期函数 | [opengauss.sql](../functions/date-functions/opengauss.sql) |
| 数学函数 | [opengauss.sql](../functions/math-functions/opengauss.sql) |
| 字符串函数 | [opengauss.sql](../functions/string-functions/opengauss.sql) |
| 类型转换 | [opengauss.sql](../functions/type-conversion/opengauss.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [opengauss.sql](../query/cte/opengauss.sql) |
| 全文搜索 | [opengauss.sql](../query/full-text-search/opengauss.sql) |
| 连接查询 | [opengauss.sql](../query/joins/opengauss.sql) |
| 分页 | [opengauss.sql](../query/pagination/opengauss.sql) |
| 行列转换 | [opengauss.sql](../query/pivot-unpivot/opengauss.sql) |
| 集合操作 | [opengauss.sql](../query/set-operations/opengauss.sql) |
| 子查询 | [opengauss.sql](../query/subquery/opengauss.sql) |
| 窗口函数 | [opengauss.sql](../query/window-functions/opengauss.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [opengauss.sql](../scenarios/date-series-fill/opengauss.sql) |
| 去重 | [opengauss.sql](../scenarios/deduplication/opengauss.sql) |
| 区间检测 | [opengauss.sql](../scenarios/gap-detection/opengauss.sql) |
| 层级查询 | [opengauss.sql](../scenarios/hierarchical-query/opengauss.sql) |
| JSON 展开 | [opengauss.sql](../scenarios/json-flatten/opengauss.sql) |
| 迁移速查 | [opengauss.sql](../scenarios/migration-cheatsheet/opengauss.sql) |
| TopN 查询 | [opengauss.sql](../scenarios/ranking-top-n/opengauss.sql) |
| 累计求和 | [opengauss.sql](../scenarios/running-total/opengauss.sql) |
| 缓慢变化维 | [opengauss.sql](../scenarios/slowly-changing-dim/opengauss.sql) |
| 字符串拆分 | [opengauss.sql](../scenarios/string-split-to-rows/opengauss.sql) |
| 窗口分析 | [opengauss.sql](../scenarios/window-analytics/opengauss.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [opengauss.sql](../types/array-map-struct/opengauss.sql) |
| 日期时间 | [opengauss.sql](../types/datetime/opengauss.sql) |
| JSON | [opengauss.sql](../types/json/opengauss.sql) |
| 数值类型 | [opengauss.sql](../types/numeric/opengauss.sql) |
| 字符串类型 | [opengauss.sql](../types/string/opengauss.sql) |
