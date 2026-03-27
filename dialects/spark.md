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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/spark.sql) | DataFrame+SQL 双接口，USING 指定数据源(Parquet/Delta/Iceberg) |
| [改表](../ddl/alter-table/spark.sql) | Delta Lake 支持 Schema Evolution，原生 Spark 表 ALTER 有限 |
| [索引](../ddl/indexes/spark.sql) | 无传统索引，Data Skipping(Delta Lake)+Z-ORDER 优化 |
| [约束](../ddl/constraints/spark.sql) | CHECK/NOT NULL(Delta Lake 3.0+)，PK/FK 不强制 |
| [视图](../ddl/views/spark.sql) | TEMPORARY VIEW(会话级)，GLOBAL TEMPORARY VIEW(应用级) |
| [序列与自增](../ddl/sequences/spark.sql) | 无 SEQUENCE，monotonically_increasing_id() 非连续 |
| [数据库/Schema/用户](../ddl/users-databases/spark.sql) | Catalog.Database.Table 三级命名空间，Unity Catalog(Databricks) |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/spark.sql) | 无动态 SQL，用 DataFrame API 构建动态查询 |
| [错误处理](../advanced/error-handling/spark.sql) | 无过程式错误处理，应用层(Scala/Python) 处理异常 |
| [执行计划](../advanced/explain/spark.sql) | EXPLAIN EXTENDED/FORMATTED，Spark UI DAG 可视化 |
| [锁机制](../advanced/locking/spark.sql) | 无行级锁，Delta Lake 提供乐观并发+冲突检测 |
| [分区](../advanced/partitioning/spark.sql) | PARTITIONED BY 文件目录分区，Bucket 分桶优化 JOIN |
| [权限](../advanced/permissions/spark.sql) | Ranger 集成，Unity Catalog(Databricks)，Storage-Based |
| [存储过程](../advanced/stored-procedures/spark.sql) | 无存储过程，UDF(Scala/Python/Java) 替代 |
| [临时表](../advanced/temp-tables/spark.sql) | CREATE TEMP VIEW 会话级，cache TABLE 缓存 |
| [事务](../advanced/transactions/spark.sql) | Delta Lake ACID 事务，原生 Spark 无事务保证 |
| [触发器](../advanced/triggers/spark.sql) | 无触发器，Structured Streaming 流式处理替代 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/spark.sql) | DELETE(Delta Lake)，原生 Spark 表不支持行级删除 |
| [插入](../dml/insert/spark.sql) | INSERT INTO/OVERWRITE，DataFrame write 模式更常用 |
| [更新](../dml/update/spark.sql) | UPDATE(Delta Lake)，原生 Spark 表不支持行级更新 |
| [Upsert](../dml/upsert/spark.sql) | MERGE INTO(Delta Lake)，功能完整 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/spark.sql) | GROUPING SETS/CUBE/ROLLUP，collect_list/collect_set |
| [条件函数](../functions/conditional/spark.sql) | IF/CASE/COALESCE/NVL/NVL2，与 Hive 兼容 |
| [日期函数](../functions/date-functions/spark.sql) | date_format/date_add/datediff，与 Hive 兼容 |
| [数学函数](../functions/math-functions/spark.sql) | 完整数学函数，与 Hive 兼容 |
| [字符串函数](../functions/string-functions/spark.sql) | concat/concat_ws，regexp_extract/replace，split |
| [类型转换](../functions/type-conversion/spark.sql) | CAST 标准，try_cast(3.4+) 安全转换 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/spark.sql) | WITH 标准+递归 CTE(3.4+)，常用于简化查询 |
| [全文搜索](../query/full-text-search/spark.sql) | 无全文搜索，依赖外部系统 |
| [连接查询](../query/joins/spark.sql) | Broadcast/Sort-Merge/Shuffle Hash JOIN，自动选择策略 |
| [分页](../query/pagination/spark.sql) | LIMIT+ORDER BY，无 OFFSET，DataFrame API take/head |
| [行列转换](../query/pivot-unpivot/spark.sql) | PIVOT/UNPIVOT(3.4+) 原生支持，stack() 函数 |
| [集合操作](../query/set-operations/spark.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/spark.sql) | 关联子查询支持(2.0+)，IN/EXISTS 标准 |
| [窗口函数](../query/window-functions/spark.sql) | 完整窗口函数，与 Hive 兼容 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/spark.sql) | sequence() 函数(2.4+) 生成日期序列+explode |
| [去重](../scenarios/deduplication/spark.sql) | ROW_NUMBER+窗口函数，dropDuplicates(DataFrame API) |
| [区间检测](../scenarios/gap-detection/spark.sql) | sequence()+窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/spark.sql) | 递归 CTE(3.4+)，之前需 DataFrame 迭代 |
| [JSON 展开](../scenarios/json-flatten/spark.sql) | from_json/json_tuple，explode 展开 JSON 数组 |
| [迁移速查](../scenarios/migration-cheatsheet/spark.sql) | Hive 兼容语法但 Delta Lake 是推荐路径，DataFrame API 更强大 |
| [TopN 查询](../scenarios/ranking-top-n/spark.sql) | ROW_NUMBER+窗口函数，LIMIT 直接 TopN |
| [累计求和](../scenarios/running-total/spark.sql) | SUM() OVER 标准，分布式并行计算 |
| [缓慢变化维](../scenarios/slowly-changing-dim/spark.sql) | MERGE INTO(Delta Lake)，功能完整 |
| [字符串拆分](../scenarios/string-split-to-rows/spark.sql) | split()+explode()/posexplode() 展开 |
| [窗口分析](../scenarios/window-analytics/spark.sql) | 完整窗口函数，ROWS/RANGE 帧支持 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/spark.sql) | ARRAY/MAP/STRUCT 原生支持，explode/posexplode 展开 |
| [日期时间](../types/datetime/spark.sql) | DATE/TIMESTAMP/TIMESTAMP_NTZ(3.4+)，无 TIME 类型 |
| [JSON](../types/json/spark.sql) | from_json/to_json 序列化，schema_of_json 推断，无 JSON 类型 |
| [数值类型](../types/numeric/spark.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/DECIMAL 标准(同 Hive) |
| [字符串类型](../types/string/spark.sql) | STRING 无长度限制，VARCHAR/CHAR(3.1+)，UTF-8 |
