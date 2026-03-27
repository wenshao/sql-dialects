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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/databricks.sql) | Delta Lake 默认，Unity Catalog 治理，CTAS 常用 |
| [改表](../ddl/alter-table/databricks.sql) | Delta Lake Schema Evolution 自动，ADD/CHANGE COLUMN |
| [索引](../ddl/indexes/databricks.sql) | 无传统索引，Data Skipping+Z-ORDER+Liquid Clustering |
| [约束](../ddl/constraints/databricks.sql) | CHECK/NOT NULL(Delta Lake)，PK/FK 信息性不强制 |
| [视图](../ddl/views/databricks.sql) | VIEW/TEMPORARY VIEW，Dynamic View(行/列级安全) |
| [序列与自增](../ddl/sequences/databricks.sql) | GENERATED ALWAYS AS IDENTITY(Delta Lake)，自增列 |
| [数据库/Schema/用户](../ddl/users-databases/databricks.sql) | Unity Catalog 三级命名空间，细粒度权限治理 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/databricks.sql) | 无动态 SQL，Python/Scala Notebook 替代 |
| [错误处理](../advanced/error-handling/databricks.sql) | 无过程式错误处理，Notebook 单元格级错误 |
| [执行计划](../advanced/explain/databricks.sql) | EXPLAIN EXTENDED+Spark UI+Photon 引擎加速 |
| [锁机制](../advanced/locking/databricks.sql) | Delta Lake 乐观并发+冲突检测，无行级锁 |
| [分区](../advanced/partitioning/databricks.sql) | PARTITIONED BY+Liquid Clustering(自动优化)替代手动分区 |
| [权限](../advanced/permissions/databricks.sql) | Unity Catalog RBAC，Row/Column Filter，Data Lineage |
| [存储过程](../advanced/stored-procedures/databricks.sql) | 无存储过程，Python UDF/Notebook 替代 |
| [临时表](../advanced/temp-tables/databricks.sql) | CREATE TEMP VIEW 会话级，Delta 表 cache |
| [事务](../advanced/transactions/databricks.sql) | Delta Lake ACID 事务，Time Travel 版本查询 |
| [触发器](../advanced/triggers/databricks.sql) | 无触发器，Delta Live Tables 声明式 ETL |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/databricks.sql) | DELETE(Delta Lake) 标准，VACUUM 清理旧版本文件 |
| [插入](../dml/insert/databricks.sql) | INSERT INTO/OVERWRITE，COPY INTO 批量加载 |
| [更新](../dml/update/databricks.sql) | UPDATE(Delta Lake) 标准，Photon 引擎加速 |
| [Upsert](../dml/upsert/databricks.sql) | MERGE INTO(Delta Lake) 功能完整 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/databricks.sql) | GROUPING SETS/CUBE/ROLLUP，collect_list/collect_set |
| [条件函数](../functions/conditional/databricks.sql) | IF/CASE/COALESCE/NVL/NVL2(Spark 兼容) |
| [日期函数](../functions/date-functions/databricks.sql) | date_format/date_add/datediff(Spark 兼容) |
| [数学函数](../functions/math-functions/databricks.sql) | 完整数学函数(Spark 兼容) |
| [字符串函数](../functions/string-functions/databricks.sql) | concat/concat_ws/regexp_extract(Spark 兼容) |
| [类型转换](../functions/type-conversion/databricks.sql) | CAST/TRY_CAST(Spark 3.4+)，类型系统同 Spark |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/databricks.sql) | WITH 标准+递归 CTE(Spark 3.4+) |
| [全文搜索](../query/full-text-search/databricks.sql) | 无内置全文搜索 |
| [连接查询](../query/joins/databricks.sql) | Broadcast/Sort-Merge/Shuffle Hash JOIN(Spark 引擎) |
| [分页](../query/pagination/databricks.sql) | LIMIT+ORDER BY(Spark 兼容)，无 OFFSET |
| [行列转换](../query/pivot-unpivot/databricks.sql) | PIVOT/UNPIVOT 原生(Spark 3.4+) |
| [集合操作](../query/set-operations/databricks.sql) | UNION/INTERSECT/EXCEPT 完整(Spark 兼容) |
| [子查询](../query/subquery/databricks.sql) | 关联子查询支持(Spark 兼容) |
| [窗口函数](../query/window-functions/databricks.sql) | 完整窗口函数(Spark 兼容)，Photon 加速 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/databricks.sql) | sequence()+explode 生成日期序列(Spark 兼容) |
| [去重](../scenarios/deduplication/databricks.sql) | ROW_NUMBER+窗口函数，dropDuplicates(DataFrame) |
| [区间检测](../scenarios/gap-detection/databricks.sql) | sequence()+窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/databricks.sql) | 递归 CTE(Spark 3.4+) |
| [JSON 展开](../scenarios/json-flatten/databricks.sql) | from_json/explode(Spark 兼容)，可直接查询 JSON 文件 |
| [迁移速查](../scenarios/migration-cheatsheet/databricks.sql) | Spark SQL 兼容+Delta Lake 扩展，Notebook 工作流 |
| [TopN 查询](../scenarios/ranking-top-n/databricks.sql) | ROW_NUMBER+窗口函数，LIMIT 直接 |
| [累计求和](../scenarios/running-total/databricks.sql) | SUM() OVER 标准(Spark 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/databricks.sql) | MERGE INTO(Delta Lake) 功能完整，Time Travel 辅助 |
| [字符串拆分](../scenarios/string-split-to-rows/databricks.sql) | split()+explode() 展开(Spark 兼容) |
| [窗口分析](../scenarios/window-analytics/databricks.sql) | 完整窗口函数(Spark 兼容)，Photon 加速 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/databricks.sql) | ARRAY/MAP/STRUCT 原生(Spark 兼容)，explode 展开 |
| [日期时间](../types/datetime/databricks.sql) | DATE/TIMESTAMP/TIMESTAMP_NTZ(Spark 兼容) |
| [JSON](../types/json/databricks.sql) | from_json/to_json(Spark 兼容)，可直接读 JSON 文件 |
| [数值类型](../types/numeric/databricks.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/DECIMAL(Spark 兼容) |
| [字符串类型](../types/string/databricks.sql) | STRING 无长度限制(Spark 兼容)，UTF-8 |
