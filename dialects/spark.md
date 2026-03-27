# Spark SQL

**分类**: 大数据计算引擎
**文件数**: 51 个 SQL 文件
**总行数**: 4707 行

## 概述与定位

Spark SQL 是 Apache Spark 大数据统一计算引擎的 SQL 层。它不是一个独立的数据库，而是运行在 Spark 之上的 SQL 接口——既可以查询 Hive 表、Parquet/ORC 文件，也可以查询 JDBC 数据源、Kafka 流等。Spark SQL 的独特价值在于**SQL 与编程 API 的无缝融合**：一个 DataFrame 既可以用 SQL 查询，也可以用 Python/Scala/Java API 操作，两者可以自由混合。

Spark SQL 的定位是"大数据批处理与流处理的统一 SQL 层"。通过 Catalyst 优化器和 Tungsten 执行引擎，它在保持 Hive 兼容性的同时，大幅超越了 Hive 的执行性能。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2009 | UC Berkeley AMPLab 启动 Spark 项目，最初定位为 MapReduce 的替代品 |
| 2014 | Apache Spark 成为顶级项目；Spark SQL 随 Spark 1.0 发布，引入 DataFrame API |
| 2015 | Spark 1.3 推出 DataFrame API（取代 SchemaRDD），Spark 1.6 引入 Dataset API |
| 2016 | Spark 2.0：统一 DataFrame 和 Dataset，引入 Structured Streaming |
| 2020 | Spark 3.0：AQE（Adaptive Query Execution）自适应查询执行、ANSI SQL 模式（默认关闭）、动态分区裁剪 |
| 2022 | Spark 3.3+：持续增强 ANSI 兼容性、DSv2 Data Source API、Pandas API on Spark |
| 2024 | Spark 4.0：ANSI 模式默认开启、Variant 类型、IDENTIFIER 子句、Collation 支持 |

## 核心设计思路

- **Catalyst 优化器**：Spark SQL 的核心。它将 SQL/DataFrame 操作统一编译为逻辑计划，然后经过规则优化（Rule-Based，如常量折叠、谓词下推）和代价优化（Cost-Based，如 Join 策略选择），最终生成物理执行计划。Catalyst 的可扩展架构允许外部开发者注入自定义优化规则。
- **Tungsten 执行引擎**：绕过 JVM 的对象模型，直接操作二进制内存布局（off-heap memory），结合 Whole-Stage Code Generation（将整个 Stage 编译为单个 Java 函数）大幅减少虚函数调用和内存开销。
- **Hive 兼容但超越**：Spark SQL 默认使用 Hive Metastore 管理表元数据，兼容 Hive SQL 语法（STORED AS、PARTITIONED BY、LATERAL VIEW 等），但在执行性能上通常比 Hive 快 10-100 倍。
- **批流一体**：Structured Streaming 将流数据视为不断追加的 DataFrame，用户可以用相同的 SQL/DataFrame API 处理批数据和流数据。虽然流处理能力不如 Flink SQL 专业，但统一的编程模型降低了学习成本。

## 独特特色

- **USING 子句指定数据源格式**：`CREATE TABLE t USING PARQUET` / `USING DELTA` / `USING JSON`。这是 Spark SQL 对 Hive 的 `STORED AS` 的扩展，通过 DataSource API 支持任意数据源插件。
- **DataFrame API 与 SQL 互通**：`df = spark.sql("SELECT ...")`、`df.createOrReplaceTempView("v")`、`spark.sql("SELECT * FROM v")`。SQL 查询结果可以立即用 API 操作，反之亦然。这种互通性在数据工程中非常实用。
- **AQE 自适应查询执行**：Spark 3.0+ 的标志性特性。在运行时根据实际数据统计信息动态调整执行计划——自动合并过小的 Shuffle 分区、自动将 Sort-Merge Join 转为 Broadcast Hash Join、自动处理数据倾斜。AQE 解决了 CBO 在统计信息不准确时的局限性。
- **Delta Lake / Iceberg 集成**：通过 Delta Lake 或 Apache Iceberg 插件，Spark SQL 获得了 ACID 事务、Time Travel、MERGE/UPDATE/DELETE 等原本缺失的能力。Delta Lake 几乎已成为 Databricks 平台的标配存储层。
- **Broadcast Hint**：`SELECT /*+ BROADCAST(small_table) */ ...` 提示优化器将小表广播到所有 Executor，避免 Shuffle Join。这是 Spark SQL 中最常用的性能优化手段之一。
- **Pandas UDF（Arrow UDF）**：通过 Apache Arrow 实现的向量化 Python UDF，性能比传统 Python UDF 快 10-100 倍。用户可以用 Pandas API 编写批处理逻辑，Spark 自动将其向量化执行。

## 已知的设计不足与历史包袱

- **无原生 UPDATE/DELETE**：原生 Spark SQL（不使用 Delta/Iceberg）不支持行级 UPDATE/DELETE。只能通过 INSERT OVERWRITE 重写整个分区。这一限制使得原生 Spark SQL 无法胜任数据修正和 SCD（缓慢变化维）场景，必须依赖 Lakehouse 层。
- **无存储过程/触发器**：Spark SQL 是纯查询引擎，不支持过程式编程。复杂逻辑需要在 Spark 应用程序（Python/Scala/Java）中实现。
- **ANSI 模式默认关闭**（4.0 之前）：默认情况下，整数溢出不报错、类型隐式转换宽松，这导致了大量隐式 bug。Spark 4.0 才将 ANSI 模式默认开启，但大量存量代码依赖非 ANSI 行为。
- **JVM 启动延迟**：Spark 基于 JVM，SparkSession 初始化、Driver/Executor 启动需要数秒甚至数十秒。对于小查询（毫秒级延迟需求），Spark SQL 并不适合。
- **小查询性能差**：Spark 的 Stage 调度、Shuffle、序列化等开销在处理小数据集时尤为明显。一个在 PostgreSQL 中 10ms 完成的查询，在 Spark SQL 中可能需要数秒。Spark SQL 的优势仅在数据量足够大时才能体现。

## 兼容生态

Spark SQL 高度兼容 Hive SQL 语法，是 Hive 的事实上的继任执行引擎。通过 Hive Metastore 集成可以无缝读写 Hive 表。Spark SQL 也通过 JDBC/ODBC（Spark Thrift Server）对外提供 SQL 服务。与 Delta Lake、Iceberg、Hudi 等 Lakehouse 格式的集成构成了现代数据湖仓的核心栈。

## 对引擎开发者的参考价值

- **Catalyst 优化器架构**：规则优化（Rule-Based Optimization）+ 代价优化（Cost-Based Optimization）的分层设计，加上 TreeNode 模式匹配的变换框架，是现代 SQL 优化器的教科书级参考。许多新兴引擎（如 Apache Calcite）受其影响。
- **Tungsten 内存管理**：证明了在 JVM 之上通过 off-heap 内存管理和代码生成可以达到接近 C++ 引擎的性能。Whole-Stage CodeGen 将操作符融合为单个函数的思路，被后续引擎广泛采用。
- **AQE 运行时重优化**：在查询执行过程中收集实际统计信息并动态调整计划的做法，解决了传统 CBO 依赖准确统计信息的固有缺陷。这一思路代表了查询优化器的未来方向。

---

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [spark.sql](../ddl/create-table/spark.sql) |
| 改表 | [spark.sql](../ddl/alter-table/spark.sql) |
| 索引 | [spark.sql](../ddl/indexes/spark.sql) |
| 约束 | [spark.sql](../ddl/constraints/spark.sql) |
| 视图 | [spark.sql](../ddl/views/spark.sql) |
| 序列与自增 | [spark.sql](../ddl/sequences/spark.sql) |
| 数据库/Schema/用户 | [spark.sql](../ddl/users-databases/spark.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [spark.sql](../advanced/dynamic-sql/spark.sql) |
| 错误处理 | [spark.sql](../advanced/error-handling/spark.sql) |
| 执行计划 | [spark.sql](../advanced/explain/spark.sql) |
| 锁机制 | [spark.sql](../advanced/locking/spark.sql) |
| 分区 | [spark.sql](../advanced/partitioning/spark.sql) |
| 权限 | [spark.sql](../advanced/permissions/spark.sql) |
| 存储过程 | [spark.sql](../advanced/stored-procedures/spark.sql) |
| 临时表 | [spark.sql](../advanced/temp-tables/spark.sql) |
| 事务 | [spark.sql](../advanced/transactions/spark.sql) |
| 触发器 | [spark.sql](../advanced/triggers/spark.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [spark.sql](../dml/delete/spark.sql) |
| 插入 | [spark.sql](../dml/insert/spark.sql) |
| 更新 | [spark.sql](../dml/update/spark.sql) |
| Upsert | [spark.sql](../dml/upsert/spark.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [spark.sql](../functions/aggregate/spark.sql) |
| 条件函数 | [spark.sql](../functions/conditional/spark.sql) |
| 日期函数 | [spark.sql](../functions/date-functions/spark.sql) |
| 数学函数 | [spark.sql](../functions/math-functions/spark.sql) |
| 字符串函数 | [spark.sql](../functions/string-functions/spark.sql) |
| 类型转换 | [spark.sql](../functions/type-conversion/spark.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [spark.sql](../query/cte/spark.sql) |
| 全文搜索 | [spark.sql](../query/full-text-search/spark.sql) |
| 连接查询 | [spark.sql](../query/joins/spark.sql) |
| 分页 | [spark.sql](../query/pagination/spark.sql) |
| 行列转换 | [spark.sql](../query/pivot-unpivot/spark.sql) |
| 集合操作 | [spark.sql](../query/set-operations/spark.sql) |
| 子查询 | [spark.sql](../query/subquery/spark.sql) |
| 窗口函数 | [spark.sql](../query/window-functions/spark.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [spark.sql](../scenarios/date-series-fill/spark.sql) |
| 去重 | [spark.sql](../scenarios/deduplication/spark.sql) |
| 区间检测 | [spark.sql](../scenarios/gap-detection/spark.sql) |
| 层级查询 | [spark.sql](../scenarios/hierarchical-query/spark.sql) |
| JSON 展开 | [spark.sql](../scenarios/json-flatten/spark.sql) |
| 迁移速查 | [spark.sql](../scenarios/migration-cheatsheet/spark.sql) |
| TopN 查询 | [spark.sql](../scenarios/ranking-top-n/spark.sql) |
| 累计求和 | [spark.sql](../scenarios/running-total/spark.sql) |
| 缓慢变化维 | [spark.sql](../scenarios/slowly-changing-dim/spark.sql) |
| 字符串拆分 | [spark.sql](../scenarios/string-split-to-rows/spark.sql) |
| 窗口分析 | [spark.sql](../scenarios/window-analytics/spark.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [spark.sql](../types/array-map-struct/spark.sql) |
| 日期时间 | [spark.sql](../types/datetime/spark.sql) |
| JSON | [spark.sql](../types/json/spark.sql) |
| 数值类型 | [spark.sql](../types/numeric/spark.sql) |
| 字符串类型 | [spark.sql](../types/string/spark.sql) |
