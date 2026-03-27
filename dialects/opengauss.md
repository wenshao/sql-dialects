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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/opengauss.sql) | PG 内核分叉(华为)，列存/行存可选，压缩表 |
| [改表](../ddl/alter-table/opengauss.sql) | PG 兼容 ALTER，在线变更 |
| [索引](../ddl/indexes/opengauss.sql) | B-tree/GIN/GiST(PG 兼容)+Ubtree(独有优化) |
| [约束](../ddl/constraints/opengauss.sql) | PK/FK/CHECK/UNIQUE(PG 兼容) |
| [视图](../ddl/views/opengauss.sql) | 物化视图(PG 兼容)，REFRESH 标准 |
| [序列与自增](../ddl/sequences/opengauss.sql) | SERIAL/IDENTITY/SEQUENCE(PG 兼容) |
| [数据库/Schema/用户](../ddl/users-databases/opengauss.sql) | PG 兼容权限+三权分立+行级安全(国产安全) |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/opengauss.sql) | EXECUTE(PL/pgSQL 兼容)+Oracle 兼容 EXECUTE IMMEDIATE |
| [错误处理](../advanced/error-handling/opengauss.sql) | EXCEPTION WHEN(PL/pgSQL 兼容) |
| [执行计划](../advanced/explain/opengauss.sql) | EXPLAIN ANALYZE(PG 兼容)，AI 调优建议(独有) |
| [锁机制](../advanced/locking/opengauss.sql) | MVCC(PG 兼容)，读不阻塞写 |
| [分区](../advanced/partitioning/opengauss.sql) | RANGE/LIST/HASH/INTERVAL 分区(PG 兼容+增强) |
| [权限](../advanced/permissions/opengauss.sql) | PG 兼容 RBAC+三权分立+数据脱敏(国产安全) |
| [存储过程](../advanced/stored-procedures/opengauss.sql) | PL/pgSQL+Oracle 兼容模式(A 数据库兼容) |
| [临时表](../advanced/temp-tables/opengauss.sql) | TEMPORARY TABLE(PG 兼容) |
| [事务](../advanced/transactions/opengauss.sql) | MVCC(PG 兼容)，DDL 事务性(PG 优势保留) |
| [触发器](../advanced/triggers/opengauss.sql) | BEFORE/AFTER/INSTEAD OF(PG 兼容) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/opengauss.sql) | DELETE/RETURNING(PG 兼容) |
| [插入](../dml/insert/opengauss.sql) | INSERT/RETURNING(PG 兼容)，ON CONFLICT |
| [更新](../dml/update/opengauss.sql) | UPDATE/RETURNING(PG 兼容) |
| [Upsert](../dml/upsert/opengauss.sql) | ON CONFLICT(PG 兼容)+MERGE(Oracle 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/opengauss.sql) | PG 兼容聚合+LISTAGG(Oracle 兼容) |
| [条件函数](../functions/conditional/opengauss.sql) | CASE/COALESCE(PG)+DECODE/NVL(Oracle 兼容) |
| [日期函数](../functions/date-functions/opengauss.sql) | PG 兼容+Oracle 兼容日期函数 |
| [数学函数](../functions/math-functions/opengauss.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/opengauss.sql) | PG 兼容+Oracle 兼容字符串函数 |
| [类型转换](../functions/type-conversion/opengauss.sql) | CAST/::(PG)+TO_NUMBER/TO_DATE(Oracle 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/opengauss.sql) | WITH+递归 CTE(PG 兼容) |
| [全文搜索](../query/full-text-search/opengauss.sql) | tsvector/tsquery(PG 兼容)+zhparser 中文分词 |
| [连接查询](../query/joins/opengauss.sql) | JOIN(PG 兼容)，LATERAL 支持 |
| [分页](../query/pagination/opengauss.sql) | LIMIT/OFFSET(PG 兼容) |
| [行列转换](../query/pivot-unpivot/opengauss.sql) | crosstab(PG 兼容 tablefunc) |
| [集合操作](../query/set-operations/opengauss.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/opengauss.sql) | 关联子查询(PG 兼容) |
| [窗口函数](../query/window-functions/opengauss.sql) | 完整窗口函数(PG 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/opengauss.sql) | generate_series(PG 兼容) |
| [去重](../scenarios/deduplication/opengauss.sql) | DISTINCT ON/ROW_NUMBER(PG 兼容) |
| [区间检测](../scenarios/gap-detection/opengauss.sql) | generate_series+窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/opengauss.sql) | 递归 CTE(PG)+CONNECT BY(Oracle 兼容) |
| [JSON 展开](../scenarios/json-flatten/opengauss.sql) | json_each/json_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/opengauss.sql) | PG 兼容+Oracle 兼容+国产安全认证是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/opengauss.sql) | ROW_NUMBER+LIMIT(PG 兼容) |
| [累计求和](../scenarios/running-total/opengauss.sql) | SUM() OVER(PG 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/opengauss.sql) | ON CONFLICT(PG)+MERGE(Oracle 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/opengauss.sql) | string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/opengauss.sql) | 完整窗口函数(PG 兼容) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/opengauss.sql) | ARRAY/复合类型(PG 兼容) |
| [日期时间](../types/datetime/opengauss.sql) | DATE/TIMESTAMP/INTERVAL(PG 兼容) |
| [JSON](../types/json/opengauss.sql) | JSON/JSONB(PG 兼容)，GIN 索引 |
| [数值类型](../types/numeric/opengauss.sql) | INTEGER/NUMERIC(PG 兼容) |
| [字符串类型](../types/string/opengauss.sql) | TEXT/VARCHAR(PG 兼容)，UTF-8 |
