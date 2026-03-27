# Databricks SQL

**分类**: Lakehouse 平台（基于 Spark）
**文件数**: 51 个 SQL 文件
**总行数**: 5095 行

## 概述与定位

Databricks SQL 是 Databricks Lakehouse 平台的 SQL 分析层，构建在 Apache Spark 之上，以 Delta Lake 开放表格式为存储基础。它提出了"Lakehouse"范式——在数据湖的低成本开放存储之上叠加数据仓库的事务性和治理能力，消除传统"数据湖 + 数据仓库"双层架构的复杂性。Databricks SQL 兼具大数据规模的弹性计算和交互式数仓的低延迟查询能力。

## 历史与演进

- **2013 年**：Databricks 由 Apache Spark 创始团队成立，最初以 Spark 作为统一大数据分析引擎。
- **2017 年**：Delta Lake 项目启动，在 Parquet 之上增加 ACID 事务、Schema 演进和时间旅行能力。
- **2020 年**：Databricks SQL（原名 SQL Analytics）发布，提供专门的 SQL 计算端点和 BI 工具集成。
- **2021 年**：Unity Catalog 发布，提供跨工作区的统一数据治理、细粒度权限和数据血缘追踪。
- **2022 年**：Photon 引擎（C++ 向量化执行引擎）成为 Databricks SQL 的默认加速器。
- **2023 年**：引入 Liquid Clustering（替代传统分区和 ZORDER）、Predictive I/O 优化。
- **2024-2025 年**：增强 Serverless 计算、AI Functions（LLM 内置 SQL 函数）、UniForm（Delta/Iceberg/Hudi 统一兼容）。

## 核心设计思路

1. **开放格式底座**：所有数据以 Delta Lake 格式（Parquet + 事务日志）存储在客户自有的对象存储中（S3/ADLS/GCS），无供应商锁定。
2. **计算存储分离**：SQL Warehouse 按需启停，数据持久化在对象存储，弹性扩缩容无数据搬运。
3. **ACID on 数据湖**：Delta Lake 提供表级 ACID 事务、MERGE/UPDATE/DELETE 支持、Schema Evolution 和 Time Travel。
4. **统一治理**：Unity Catalog 提供从表、列到行级别的权限控制，以及自动化的数据血缘追踪。

## 独特特色

| 特性 | 说明 |
|---|---|
| **Delta Lake ACID** | 在 Parquet 之上通过事务日志实现 ACID 事务，支持并发写入冲突检测、乐观并发控制。 |
| **Unity Catalog** | 跨工作区的三级命名空间（Catalog.Schema.Table）、列级权限、标签分类和自动血缘。 |
| **Liquid Clustering** | 替代传统静态分区的自适应聚类策略，数据写入时自动优化布局，无需 ZORDER 手动维护。 |
| **Photon 引擎** | C++ 编写的向量化执行引擎，替代 Spark JVM 执行，扫描和聚合性能提升数倍。 |
| **Time Travel** | `SELECT * FROM t VERSION AS OF 5` 或 `TIMESTAMP AS OF '2024-01-01'` 查询历史版本数据。 |
| **MERGE INTO** | 完整的 CDC（变更数据捕获）语法，支持 WHEN MATCHED / WHEN NOT MATCHED / WHEN NOT MATCHED BY SOURCE。 |
| **AI Functions** | `ai_generate_text()`、`ai_classify()` 等 SQL 函数直接在查询中调用大语言模型。 |

## 已知不足

- **冷启动延迟**：SQL Warehouse 从暂停状态恢复需要数十秒到数分钟，不适合极低延迟的在线查询场景。
- **小文件问题**：高频小批量写入会产生大量小 Parquet 文件，需定期 OPTIMIZE 合并（虽有 Auto Optimize，但仍需关注）。
- **存储过程有限**：Databricks SQL 的过程化编程能力依赖 Notebooks/Python UDF，纯 SQL 存储过程支持不如传统数仓。
- **成本控制复杂**：DBU（Databricks Unit）定价模型加上底层云存储/网络费用，总成本估算对用户不够透明。
- **索引能力弱**：无传统 B-tree 索引，依赖 Liquid Clustering、Bloom Filter 和文件级统计信息进行查询加速。

## 对引擎开发者的参考价值

- **Delta Lake 事务日志设计**：用 JSON 事务日志（+ Checkpoint）实现在不可变文件之上的 ACID 语义，对数据湖引擎的事务实现有核心参考。
- **Photon 向量化引擎**：从 JVM 切换到 C++ 向量化执行的实践，展示了在保持上层 SQL 兼容的前提下替换执行层的可行路径。
- **Liquid Clustering 自适应布局**：运行时根据数据分布自动调整物理布局的策略，对列存引擎的自适应分区设计有启发。
- **Unity Catalog 治理模型**：跨工作区的统一元数据 + 细粒度权限 + 自动血缘的设计，对多租户引擎的 Catalog 层设计有参考价值。
- **开放格式互操作（UniForm）**：使同一份数据同时对 Delta/Iceberg/Hudi 客户端可读的元数据转换层设计，对存储格式兼容层有借鉴意义。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [databricks.sql](../ddl/create-table/databricks.sql) |
| 改表 | [databricks.sql](../ddl/alter-table/databricks.sql) |
| 索引 | [databricks.sql](../ddl/indexes/databricks.sql) |
| 约束 | [databricks.sql](../ddl/constraints/databricks.sql) |
| 视图 | [databricks.sql](../ddl/views/databricks.sql) |
| 序列与自增 | [databricks.sql](../ddl/sequences/databricks.sql) |
| 数据库/Schema/用户 | [databricks.sql](../ddl/users-databases/databricks.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [databricks.sql](../advanced/dynamic-sql/databricks.sql) |
| 错误处理 | [databricks.sql](../advanced/error-handling/databricks.sql) |
| 执行计划 | [databricks.sql](../advanced/explain/databricks.sql) |
| 锁机制 | [databricks.sql](../advanced/locking/databricks.sql) |
| 分区 | [databricks.sql](../advanced/partitioning/databricks.sql) |
| 权限 | [databricks.sql](../advanced/permissions/databricks.sql) |
| 存储过程 | [databricks.sql](../advanced/stored-procedures/databricks.sql) |
| 临时表 | [databricks.sql](../advanced/temp-tables/databricks.sql) |
| 事务 | [databricks.sql](../advanced/transactions/databricks.sql) |
| 触发器 | [databricks.sql](../advanced/triggers/databricks.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [databricks.sql](../dml/delete/databricks.sql) |
| 插入 | [databricks.sql](../dml/insert/databricks.sql) |
| 更新 | [databricks.sql](../dml/update/databricks.sql) |
| Upsert | [databricks.sql](../dml/upsert/databricks.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [databricks.sql](../functions/aggregate/databricks.sql) |
| 条件函数 | [databricks.sql](../functions/conditional/databricks.sql) |
| 日期函数 | [databricks.sql](../functions/date-functions/databricks.sql) |
| 数学函数 | [databricks.sql](../functions/math-functions/databricks.sql) |
| 字符串函数 | [databricks.sql](../functions/string-functions/databricks.sql) |
| 类型转换 | [databricks.sql](../functions/type-conversion/databricks.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [databricks.sql](../query/cte/databricks.sql) |
| 全文搜索 | [databricks.sql](../query/full-text-search/databricks.sql) |
| 连接查询 | [databricks.sql](../query/joins/databricks.sql) |
| 分页 | [databricks.sql](../query/pagination/databricks.sql) |
| 行列转换 | [databricks.sql](../query/pivot-unpivot/databricks.sql) |
| 集合操作 | [databricks.sql](../query/set-operations/databricks.sql) |
| 子查询 | [databricks.sql](../query/subquery/databricks.sql) |
| 窗口函数 | [databricks.sql](../query/window-functions/databricks.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [databricks.sql](../scenarios/date-series-fill/databricks.sql) |
| 去重 | [databricks.sql](../scenarios/deduplication/databricks.sql) |
| 区间检测 | [databricks.sql](../scenarios/gap-detection/databricks.sql) |
| 层级查询 | [databricks.sql](../scenarios/hierarchical-query/databricks.sql) |
| JSON 展开 | [databricks.sql](../scenarios/json-flatten/databricks.sql) |
| 迁移速查 | [databricks.sql](../scenarios/migration-cheatsheet/databricks.sql) |
| TopN 查询 | [databricks.sql](../scenarios/ranking-top-n/databricks.sql) |
| 累计求和 | [databricks.sql](../scenarios/running-total/databricks.sql) |
| 缓慢变化维 | [databricks.sql](../scenarios/slowly-changing-dim/databricks.sql) |
| 字符串拆分 | [databricks.sql](../scenarios/string-split-to-rows/databricks.sql) |
| 窗口分析 | [databricks.sql](../scenarios/window-analytics/databricks.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [databricks.sql](../types/array-map-struct/databricks.sql) |
| 日期时间 | [databricks.sql](../types/datetime/databricks.sql) |
| JSON | [databricks.sql](../types/json/databricks.sql) |
| 数值类型 | [databricks.sql](../types/numeric/databricks.sql) |
| 字符串类型 | [databricks.sql](../types/string/databricks.sql) |
