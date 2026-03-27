# Apache Impala

**分类**: Hadoop SQL 引擎（Cloudera）
**文件数**: 51 个 SQL 文件
**总行数**: 4626 行

## 概述与定位

Apache Impala 是 Cloudera 开发的 Hadoop 生态实时 SQL 查询引擎，旨在为 HDFS 和 HBase 上的数据提供低延迟的交互式分析能力。与 Hive 的 MapReduce/Tez 批处理模式不同，Impala 使用常驻守护进程（impalad）和 MPP 架构直接在数据节点上执行查询，跳过了 MapReduce 的调度开销，将查询延迟从分钟级降低到秒级。Impala 共享 Hive Metastore，使得同一份数据可被 Hive、Spark 和 Impala 共同访问。

## 历史与演进

- **2012 年**：Cloudera 发布 Impala 1.0 Beta，定位为 Hadoop 上的"实时 SQL"引擎。
- **2013 年**：Impala 1.0 GA，支持 HDFS/HBase 查询、UDF、Parquet 格式原生支持。
- **2015 年**：Impala 2.x 引入多租户资源管理（Admission Control）、COMPUTE STATS 优化器增强。
- **2017 年**：Impala 成为 Apache 顶级项目，增加 Kudu 表支持（可变数据存储）。
- **2019 年**：Impala 3.x 增强 ACID 支持（通过 Hive ACID 表）、改进窗口函数和分析功能。
- **2022 年**：Impala 4.x 引入 Iceberg 表支持、虚拟仓库部署（Impala on K8s）、存算分离。
- **2024-2025 年**：持续推进云原生部署、增强对 Iceberg V2 的支持、改进并发查询性能。

## 核心设计思路

1. **常驻进程 MPP**：每个数据节点运行 impalad 守护进程，查询到达后直接并行执行，无需启动 MapReduce 作业。
2. **共享 Hive Metastore**：与 Hive 共享表元数据，`INVALIDATE METADATA` / `REFRESH` 命令同步元数据变更。
3. **代码生成**：使用 LLVM 进行运行时代码生成（Codegen），为每个查询生成针对具体 schema 的优化机器码。
4. **多存储后端**：支持 HDFS（Parquet/ORC/Text）、Kudu（可变列存）、HBase（KV 存储）和 S3/ADLS 等多种存储。

## 独特特色

| 特性 | 说明 |
|---|---|
| **Kudu 表** | 原生集成 Apache Kudu，在 Hadoop 生态中提供可变列式存储，支持实时 INSERT/UPDATE/DELETE，弥补 HDFS 不可变的不足。 |
| **COMPUTE STATS** | `COMPUTE STATS table_name` 收集表和列的统计信息（行数、NDV、NULL 比例等），是优化器生成高效计划的关键。 |
| **INVALIDATE METADATA** | 当外部工具（Hive/Spark）修改了表结构或数据后，通过此命令强制 Impala 重新加载元数据缓存。 |
| **LLVM 代码生成** | 运行时为每个查询生成特化的 C++ 代码，消除解释执行的开销，对扫描密集型查询性能提升显著。 |
| **Admission Control** | 内置的资源准入控制，基于队列限制并发查询数和内存使用，避免集群过载。 |
| **分区裁剪** | 深度优化的分区裁剪逻辑，配合 Parquet 的行组统计信息实现多层过滤（分区级 + 文件级 + 行组级）。 |
| **Parquet 原生支持** | Impala 是 Parquet 格式的最早采用者之一，在读取和写入 Parquet 文件方面有深度优化。 |

## 已知不足

- **不支持 UPDATE/DELETE（HDFS 表）**：对 HDFS 上的 Parquet/ORC 表不支持行级更新和删除，仅 Kudu 表支持。
- **SQL 功能受限**：不支持存储过程、触发器、游标；CTE 支持较晚；JSON 处理能力有限。
- **元数据同步开销**：频繁 INVALIDATE METADATA 在大规模集群（数万表）上可能导致 Catalogd 压力过大。
- **容错能力弱**：查询执行期间如有节点故障，整个查询失败（无重试机制），不适合超长运行的批处理查询。
- **生态萎缩**：随着 Spark SQL、Trino/Presto 和云数仓的崛起，Impala 的独立部署用户逐渐减少。
- **资源争用**：与 HDFS DataNode 共享节点资源，高并发查询时可能与 HDFS I/O 和 YARN 作业产生资源冲突。

## 对引擎开发者的参考价值

- **LLVM 运行时代码生成**：Impala 是 OLAP 引擎中最早大规模使用 LLVM Codegen 的项目之一，其 Expr Codegen 和 Scan Codegen 的实现对查询引擎加速有核心参考。
- **常驻进程 vs 作业调度**：与 Hive 的按需启动模式对比，Impala 的常驻进程模式展示了延迟与资源利用率的权衡。
- **Metastore 缓存一致性**：INVALIDATE / REFRESH 的两级缓存失效策略，对分布式 Catalog 的一致性设计有实践参考。
- **多存储后端抽象**：通过统一的 ScanNode 抽象层对接 HDFS/Kudu/HBase/S3 等不同存储，对插件化存储后端的设计有借鉴。
- **Admission Control 模型**：基于队列的资源准入控制（而非严格的资源隔离），是轻量级多租户管理的实用方案。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/impala.sql) | MPP 查询引擎(HDFS/Kudu/HBase)，STORED AS 指定格式 |
| [改表](../ddl/alter-table/impala.sql) | ADD/DROP/CHANGE COLUMN，Kudu 表支持更多 ALTER |
| [索引](../ddl/indexes/impala.sql) | 无索引(HDFS 查询引擎)，Kudu 主键排序替代 |
| [约束](../ddl/constraints/impala.sql) | Kudu 表 PK/NOT NULL，HDFS 表无约束 |
| [视图](../ddl/views/impala.sql) | 普通视图，无物化视图 |
| [序列与自增](../ddl/sequences/impala.sql) | 无 SEQUENCE/自增，UUID()/ROW_NUMBER 替代 |
| [数据库/Schema/用户](../ddl/users-databases/impala.sql) | Hive Metastore 共享元数据，Ranger/Sentry 权限 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/impala.sql) | 无动态 SQL(查询引擎定位) |
| [错误处理](../advanced/error-handling/impala.sql) | 无过程式错误处理 |
| [执行计划](../advanced/explain/impala.sql) | EXPLAIN/PROFILE 查看 MPP 执行计划和资源消耗 |
| [锁机制](../advanced/locking/impala.sql) | 无行级锁(查询引擎定位)，Kudu 有 MVCC |
| [分区](../advanced/partitioning/impala.sql) | PARTITIONED BY(同 Hive)，COMPUTE STATS 统计信息 |
| [权限](../advanced/permissions/impala.sql) | Ranger/Sentry 集成，与 Hive 共享权限策略 |
| [存储过程](../advanced/stored-procedures/impala.sql) | 无存储过程，UDF(C++/Java) 替代 |
| [临时表](../advanced/temp-tables/impala.sql) | 无传统临时表(共享 Hive Metastore) |
| [事务](../advanced/transactions/impala.sql) | Kudu 表支持 INSERT/UPDATE/DELETE，HDFS 表追加写入 |
| [触发器](../advanced/triggers/impala.sql) | 无触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/impala.sql) | DELETE(仅 Kudu 表)，HDFS 表不支持行级删除 |
| [插入](../dml/insert/impala.sql) | INSERT INTO/OVERWRITE(同 Hive)，Kudu INSERT |
| [更新](../dml/update/impala.sql) | UPDATE(仅 Kudu 表)，UPSERT 支持 |
| [Upsert](../dml/upsert/impala.sql) | UPSERT(仅 Kudu 表，原生支持) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/impala.sql) | GROUPING SETS/ROLLUP/CUBE(3.x+)，NDV 近似计数 |
| [条件函数](../functions/conditional/impala.sql) | IF/CASE/COALESCE/NVL/IFNULL 标准 |
| [日期函数](../functions/date-functions/impala.sql) | FROM_UNIXTIME/UNIX_TIMESTAMP/DATE_ADD，Hive 兼容 |
| [数学函数](../functions/math-functions/impala.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/impala.sql) | CONCAT/SUBSTR/REGEXP_REPLACE(Hive 兼容) |
| [类型转换](../functions/type-conversion/impala.sql) | CAST 标准，隐式转换较宽松 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/impala.sql) | WITH 标准+递归 CTE(4.x+) |
| [全文搜索](../query/full-text-search/impala.sql) | 无全文搜索 |
| [连接查询](../query/joins/impala.sql) | Broadcast/Partitioned Hash JOIN，JOIN 策略提示 |
| [分页](../query/pagination/impala.sql) | LIMIT/OFFSET 标准 |
| [行列转换](../query/pivot-unpivot/impala.sql) | 无原生 PIVOT，CASE+GROUP BY |
| [集合操作](../query/set-operations/impala.sql) | UNION/INTERSECT/EXCEPT(3.x+) |
| [子查询](../query/subquery/impala.sql) | IN/EXISTS 子查询(2.x+)，关联子查询 |
| [窗口函数](../query/window-functions/impala.sql) | 完整窗口函数支持(2.0+)，ROWS/RANGE 帧 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/impala.sql) | 无 generate_series，需辅助表或应用层生成 |
| [去重](../scenarios/deduplication/impala.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/impala.sql) | 窗口函数 LAG/LEAD 检测 |
| [层级查询](../scenarios/hierarchical-query/impala.sql) | 递归 CTE(4.x+) |
| [JSON 展开](../scenarios/json-flatten/impala.sql) | GET_JSON_OBJECT/JSON_EXTRACT(Hive 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/impala.sql) | Hive 兼容查询引擎，Kudu/HDFS 双模式是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/impala.sql) | ROW_NUMBER+LIMIT 标准 |
| [累计求和](../scenarios/running-total/impala.sql) | SUM() OVER 标准，MPP 并行 |
| [缓慢变化维](../scenarios/slowly-changing-dim/impala.sql) | UPSERT(Kudu 表)，HDFS 表 INSERT OVERWRITE |
| [字符串拆分](../scenarios/string-split-to-rows/impala.sql) | 无原生拆分函数，需 UDF 或应用层处理 |
| [窗口分析](../scenarios/window-analytics/impala.sql) | 完整窗口函数(2.0+)，MPP 并行 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/impala.sql) | ARRAY/MAP/STRUCT(Parquet/ORC 嵌套)，COMPLEX TYPES |
| [日期时间](../types/datetime/impala.sql) | TIMESTAMP(纳秒)/DATE(3.x+)，无 TIME/INTERVAL |
| [JSON](../types/json/impala.sql) | GET_JSON_OBJECT 路径查询，无 JSON 类型 |
| [数值类型](../types/numeric/impala.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/DECIMAL(38) 标准 |
| [字符串类型](../types/string/impala.sql) | STRING 无长度限制，VARCHAR/CHAR，UTF-8 |
