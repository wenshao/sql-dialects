# Apache Hive

**分类**: Hadoop 数仓（Apache）
**文件数**: 51 个 SQL 文件
**总行数**: 4629 行

## 概述与定位

Apache Hive 是大数据 SQL 化的开创者，首次让非 Java 程序员可以用 SQL 查询 Hadoop 上的海量数据。它的核心贡献不在于执行引擎本身（底层先后依赖 MapReduce、Tez、LLAP），而在于**定义了大数据 SQL 的语法标准和元数据管理模式**——Hive Metastore 至今仍是 Hadoop 生态中最重要的元数据服务。

Hive 的定位是"数据仓库基础设施"：它定义了表、分区、存储格式之间的映射关系，提供了 SQL 到分布式计算的编译能力。虽然在实时查询场景中已被 Spark SQL、Presto/Trino 等引擎超越，但 Hive 的元数据模型和 SQL 方言影响深远。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2007 | Facebook 内部项目启动，目标是让分析师用 SQL 查询 HDFS 数据 |
| 2010 | 成为 Apache 顶级项目 |
| 2013 | Stinger Initiative（Hive 0.13）：引入 ORC 格式、Vectorized Query、Cost-Based Optimizer |
| 2016 | Hive 2.0：LLAP（Live Long And Process）常驻执行守护进程，大幅降低延迟 |
| 2018 | Hive 3.0：完整 ACID 事务支持（基于 ORC + Delta 文件），废弃索引功能 |
| 2020+ | 社区活跃度下降，但 Hive Metastore 作为独立服务持续被 Spark/Presto/Trino/Flink 等引擎依赖 |

## 核心设计思路

- **Schema-on-Read**：Hive 的核心理念是"先存储后定义结构"。数据以文件形式存放在 HDFS 上，建表时通过 SerDe（序列化/反序列化器）告诉 Hive 如何解读文件内容。这意味着同一份数据可以用不同 Schema 查询——表结构不绑定存储格式。
- **分区 = 目录**：`PARTITIONED BY (dt STRING)` 意味着每个分区值对应 HDFS 上的一个子目录（如 `/warehouse/t/dt=2024-01-01/`）。分区裁剪就是跳过不相关的目录。这一简单直接的映射关系使得分区管理透明且可预测。
- **SerDe 可插拔序列化**：Hive 通过 SerDe 接口支持任意数据格式——CSV、JSON、Avro、ORC、Parquet 等。用户甚至可以实现自定义 SerDe 读取特殊格式。这种可插拔设计是 Hive 能处理多样数据格式的关键。
- **INSERT OVERWRITE 为主要写入模式**：Hive 传统上不支持行级 UPDATE/DELETE，而是通过 `INSERT OVERWRITE` 整体重写分区。这一设计与 HDFS 的"一次写入多次读取"特性吻合——HDFS 不支持随机写入，重写整个分区反而是最高效的方式。
- **外部表概念**：`CREATE EXTERNAL TABLE` 不管理数据生命周期——DROP TABLE 只删除元数据不删除文件。这使得 Hive 可以安全地叠加在已有数据之上，不影响其他系统对数据的访问。

## 独特特色

- **STORED AS 子句**：`STORED AS ORC`、`STORED AS PARQUET` 直接在建表语句中声明存储格式，将物理存储选择提升为 DDL 级别的一等概念。这一设计被后来的 Spark SQL 完全继承。
- **PARTITIONED BY (目录级分区)**：分区列不存储在数据文件中，而是编码在目录路径里。这使得添加/删除分区非常轻量（仅操作元数据和目录），但也导致了小文件问题——分区过多会产生大量小文件。
- **INSERT OVERWRITE**：幂等写入——无论执行多少次，结果相同。这一特性天然适合批处理 ETL：失败重试不会产生重复数据。
- **LATERAL VIEW explode**：将数组列展开为多行的标准方式。`LATERAL VIEW explode(tags) t AS tag` 是 Hive 对嵌套数据的标志性处理手法。
- **SORT BY / DISTRIBUTE BY / CLUSTER BY**：Hive 区分了全局排序（ORDER BY）、Reducer 内排序（SORT BY）、数据分发（DISTRIBUTE BY）和分发+排序（CLUSTER BY），反映了底层 MapReduce 的执行模型。
- **UDF/UDAF/UDTF 接口**：三级用户自定义函数接口——标量函数(UDF)、聚合函数(UDAF)、表生成函数(UDTF)。虽然 API 设计较老旧，但定义了大数据 SQL 自定义函数的基本范式。

## 已知的设计不足与历史包袱

- **早期无 UPDATE/DELETE**：Hive 3.0 之前完全不支持行级更新和删除。即使 3.0+ 支持 ACID 表，也必须使用 ORC 格式且配置事务管理器，性能远不及传统 RDBMS。
- **无索引（3.0 废弃）**：Hive 曾有有限的索引支持，但效果不佳，在 3.0 版本正式废弃。替代方案是依赖 ORC/Parquet 的内置 min/max 统计信息和 Bloom Filter。
- **MapReduce 延迟高**：传统 MapReduce 执行引擎启动一个简单查询可能需要 30-60 秒。虽然 Tez 和 LLAP 大幅改善了延迟，但 Hive 的"批处理基因"使得它在交互式查询场景中仍然不够快。
- **Metastore 单点问题**：Hive Metastore 基于关系数据库（通常是 MySQL/PostgreSQL），在大规模集群中可能成为瓶颈。分区数过多（数万级别）会导致 Metastore 操作缓慢。
- **CTE 不支持递归**：Hive 的 WITH 子句仅用于查询重用，不支持递归 CTE，无法用 SQL 直接表达层级查询。
- **ACID 性能有限**：Hive ACID 通过 Delta 文件 + Compaction 实现，读取时需要合并 base 文件和多个 delta 文件，性能开销大，不适合高并发事务场景。

## 兼容生态

Hive SQL 方言是大数据领域的"通用语"。以下引擎高度兼容或直接复用 Hive 语法：
- **Spark SQL**：默认兼容 Hive 语法，可直接读写 Hive Metastore 中的表
- **Databricks**：基于 Spark SQL，继承 Hive 兼容性
- **MaxCompute（阿里云）**：早期版本几乎完全兼容 Hive SQL
- **Impala**：共享 Hive Metastore，SQL 语法高度兼容
- **Flink SQL**：通过 HiveCatalog 集成 Hive Metastore，支持读写 Hive 表
- **Presto/Trino**：通过 Hive Connector 访问 Hive Metastore 管理的数据

## 对引擎开发者的参考价值

- **分区 = 目录的设计模式**：将逻辑分区映射为物理目录结构，简单、透明、可预测。这一模式被 Delta Lake、Iceberg、Hudi 等现代 Lakehouse 格式继承并改进（它们用 manifest 文件替代了目录列表以解决小文件和原子性问题）。
- **SerDe 架构**：将数据格式的序列化/反序列化抽象为可插拔接口，使存储引擎与查询引擎解耦。这一思想影响了后续几乎所有大数据 SQL 引擎的数据源抽象设计。
- **INSERT OVERWRITE 的幂等写入**：在分布式系统中，幂等操作是故障恢复的基础。INSERT OVERWRITE 通过"整体替换"而非"增量追加"天然实现幂等性，这一模式至今仍是批处理 ETL 的最佳实践。

---

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [hive.sql](../ddl/create-table/hive.sql) |
| 改表 | [hive.sql](../ddl/alter-table/hive.sql) |
| 索引 | [hive.sql](../ddl/indexes/hive.sql) |
| 约束 | [hive.sql](../ddl/constraints/hive.sql) |
| 视图 | [hive.sql](../ddl/views/hive.sql) |
| 序列与自增 | [hive.sql](../ddl/sequences/hive.sql) |
| 数据库/Schema/用户 | [hive.sql](../ddl/users-databases/hive.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [hive.sql](../advanced/dynamic-sql/hive.sql) |
| 错误处理 | [hive.sql](../advanced/error-handling/hive.sql) |
| 执行计划 | [hive.sql](../advanced/explain/hive.sql) |
| 锁机制 | [hive.sql](../advanced/locking/hive.sql) |
| 分区 | [hive.sql](../advanced/partitioning/hive.sql) |
| 权限 | [hive.sql](../advanced/permissions/hive.sql) |
| 存储过程 | [hive.sql](../advanced/stored-procedures/hive.sql) |
| 临时表 | [hive.sql](../advanced/temp-tables/hive.sql) |
| 事务 | [hive.sql](../advanced/transactions/hive.sql) |
| 触发器 | [hive.sql](../advanced/triggers/hive.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [hive.sql](../dml/delete/hive.sql) |
| 插入 | [hive.sql](../dml/insert/hive.sql) |
| 更新 | [hive.sql](../dml/update/hive.sql) |
| Upsert | [hive.sql](../dml/upsert/hive.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [hive.sql](../functions/aggregate/hive.sql) |
| 条件函数 | [hive.sql](../functions/conditional/hive.sql) |
| 日期函数 | [hive.sql](../functions/date-functions/hive.sql) |
| 数学函数 | [hive.sql](../functions/math-functions/hive.sql) |
| 字符串函数 | [hive.sql](../functions/string-functions/hive.sql) |
| 类型转换 | [hive.sql](../functions/type-conversion/hive.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [hive.sql](../query/cte/hive.sql) |
| 全文搜索 | [hive.sql](../query/full-text-search/hive.sql) |
| 连接查询 | [hive.sql](../query/joins/hive.sql) |
| 分页 | [hive.sql](../query/pagination/hive.sql) |
| 行列转换 | [hive.sql](../query/pivot-unpivot/hive.sql) |
| 集合操作 | [hive.sql](../query/set-operations/hive.sql) |
| 子查询 | [hive.sql](../query/subquery/hive.sql) |
| 窗口函数 | [hive.sql](../query/window-functions/hive.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [hive.sql](../scenarios/date-series-fill/hive.sql) |
| 去重 | [hive.sql](../scenarios/deduplication/hive.sql) |
| 区间检测 | [hive.sql](../scenarios/gap-detection/hive.sql) |
| 层级查询 | [hive.sql](../scenarios/hierarchical-query/hive.sql) |
| JSON 展开 | [hive.sql](../scenarios/json-flatten/hive.sql) |
| 迁移速查 | [hive.sql](../scenarios/migration-cheatsheet/hive.sql) |
| TopN 查询 | [hive.sql](../scenarios/ranking-top-n/hive.sql) |
| 累计求和 | [hive.sql](../scenarios/running-total/hive.sql) |
| 缓慢变化维 | [hive.sql](../scenarios/slowly-changing-dim/hive.sql) |
| 字符串拆分 | [hive.sql](../scenarios/string-split-to-rows/hive.sql) |
| 窗口分析 | [hive.sql](../scenarios/window-analytics/hive.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [hive.sql](../types/array-map-struct/hive.sql) |
| 日期时间 | [hive.sql](../types/datetime/hive.sql) |
| JSON | [hive.sql](../types/json/hive.sql) |
| 数值类型 | [hive.sql](../types/numeric/hive.sql) |
| 字符串类型 | [hive.sql](../types/string/hive.sql) |
