# Flink SQL

**分类**: 流批一体计算引擎
**文件数**: 51 个 SQL 文件
**总行数**: 5042 行

## 概述与定位

Flink SQL 是 Apache Flink 流批一体计算引擎的 SQL 层，是当前**实时流计算领域最成熟的 SQL 引擎**。与 Spark SQL 以批处理为核心再扩展到流不同，Flink 从设计之初就以流处理为第一优先级（Stream-first），批处理被视为流处理的特例（有界流）。

Flink SQL 的核心价值在于：让用户用标准 SQL 编写实时数据管道，无需学习底层的 DataStream API。一条 `INSERT INTO sink SELECT ... FROM source` 语句就能启动一个持续运行的流处理作业。这极大降低了实时计算的门槛，使得 SQL 分析师也能构建实时数据管道。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2010 | 柏林工业大学（TU Berlin）启动 Stratosphere 研究项目 |
| 2014 | 进入 Apache 孵化器，更名为 Flink（德语"敏捷"） |
| 2016 | 阿里巴巴 fork 出 Blink 分支，在内部大规模部署用于双十一实时大屏 |
| 2019 | Flink 1.9：合并 Blink 回主线，Table API / SQL 大幅增强 |
| 2021 | Flink 1.13：引入窗口 TVF（Table-Valued Function），统一窗口语法 |
| 2023 | Flink 1.18+：持续增强批模式、Materialized Table、流式 Lakehouse 集成 |

## 核心设计思路

- **流优先（Stream-first）**：Flink 的执行模型基于持续运行的算子图（DAG），数据以事件的形式在算子间流动。批处理只是将数据源标记为"有界"的流处理。这一设计使得 Flink SQL 在表达流式语义时非常自然，但也导致一些批处理场景下的功能和性能不如 Spark SQL。
- **事件时间 + Watermark**：Flink 区分事件时间（Event Time，数据自带的时间戳）和处理时间（Processing Time，系统当前时间）。Watermark 是 Flink 处理乱序数据的核心机制——它声明"不会再有早于此时间戳的数据到达"，从而触发窗口计算。这一设计使 Flink 能正确处理延迟到达的数据。
- **Connector 架构**：Flink SQL 通过 `WITH (...)` 子句在 DDL 中声明数据源和目标的连接参数（如 Kafka topic、JDBC URL）。Connector 是 Flink SQL 的"输入输出接口"，支持 Kafka、MySQL CDC、HBase、Elasticsearch、FileSystem 等数十种外部系统。
- **时间窗口 TVF**：Flink 1.13+ 引入的窗口表值函数（`TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' HOUR)`），替代了旧的 GROUP BY TUMBLE() 语法，使窗口成为 FROM 子句中的一等公民，支持窗口 JOIN、窗口 TopN 等复合操作。

## 独特特色

- **WATERMARK 定义**：在 DDL 中直接声明水印策略，如 `WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND`。这是 Flink SQL 独有的语法，将流式语义嵌入了 SQL DDL。
- **PROCTIME()**：虚拟列函数，声明处理时间属性。`proc_time AS PROCTIME()` 为表添加一个总是返回当前系统时间的虚拟列，用于处理时间窗口。
- **窗口 TVF 家族**：TUMBLE（滚动窗口）、HOP（滑动窗口）、SESSION（会话窗口）、CUMULATE（累积窗口）。四种窗口覆盖了绝大多数实时聚合场景。CUMULATE 是 Flink 独创——在一个大窗口内按步长逐步扩展，适合"每分钟更新的小时累计"场景。
- **Temporal Join（时态 Join）**：`FOR SYSTEM_TIME AS OF` 语法实现的版本化 Join，将流数据与维表的历史版本关联。例如将订单流与汇率表的历史版本 Join，获取下单时刻的汇率。这是流处理独有的语义需求。
- **Lookup Join**：流表与外部维表（如 MySQL、HBase）的点查 Join。Flink 运行时对每条流数据发起维表查询，支持缓存和异步 I/O 优化。这一模式在实时数仓中极为常见。
- **Interval Join**：基于时间区间的流流 Join，如 `ON a.ts BETWEEN b.ts - INTERVAL '5' MINUTE AND b.ts + INTERVAL '5' MINUTE`。限制 Join 的时间范围以控制状态大小。
- **MATCH_RECOGNIZE**：SQL 标准中的复杂事件处理（CEP）语法，用正则表达式匹配事件序列。例如检测"连续三次登录失败后成功"的模式。Flink 是少数完整实现此语法的引擎之一。
- **Changelog 语义**：Flink SQL 内部用四种消息类型编码数据变更——INSERT、UPDATE_BEFORE、UPDATE_AFTER、DELETE。这使得 Flink 可以在流上表达完整的关系代数操作（包括 GROUP BY 聚合的更新），而不仅仅是追加。这一设计是 Flink SQL 区别于大多数流引擎的关键。
- **Connector WITH 子句**：`CREATE TABLE t (...) WITH ('connector' = 'kafka', 'topic' = 'orders', ...)`。将外部系统的连接信息内嵌在 DDL 中，使得一条 SQL 就能完整描述一个数据管道的输入输出。
- **Paimon 集成**：Apache Paimon（原 Flink Table Store）是 Flink 原生的数据湖表格式。支持流式写入 + 批量读取，Changelog 语义天然对齐。`CREATE TABLE ... WITH ('connector'='paimon')`。对标 Delta Lake/Iceberg 但更适合流处理场景。
- **State TTL**：`'table.exec.state.ttl' = '1h'` 控制算子状态的过期时间。防止 JOIN/聚合的状态无限增长导致 OOM。这是 Flink SQL 生产化的关键配置——设短了丢数据，设长了 OOM。
- **Mini-batch 优化**：`'table.exec.mini-batch.enabled' = 'true'` 将单条处理变为微批处理，减少状态访问次数和下游输出频率。对高 QPS 场景性能提升 3-10×。
- **Unaligned Checkpoint**：允许在 backpressure 时仍然完成 checkpoint，避免长时间阻塞导致 checkpoint 超时失败。对生产稳定性至关重要。

## 已知的设计不足与历史包袱

- **无传统 UPDATE/DELETE**：Flink SQL 的 DML 只有 `INSERT INTO`。数据修正需要通过发送 Changelog 消息（UPDATE_BEFORE + UPDATE_AFTER）实现，对普通 SQL 用户来说概念陌生。
- **无索引**：Flink 是计算引擎而非存储引擎，不管理持久化数据，因此索引概念不适用。
- **无存储过程/触发器**：不支持过程式编程，所有逻辑必须用声明式 SQL 或底层 DataStream API 表达。
- **批模式功能弱于 Spark**：虽然 Flink 支持批处理，但生态成熟度（数据源支持、优化器完善度、社区经验）远不及 Spark SQL。大多数用户在批场景中仍选择 Spark。
- **状态管理复杂**：流作业需要维护状态（如窗口聚合的中间结果、Join 的双侧缓存）。状态过大会导致 Checkpoint 超时和恢复缓慢。State TTL 配置不当会导致结果不正确或 OOM。这是 Flink SQL 运维中最常见的痛点。
- **调试困难**：流作业持续运行，错误可能在运行数小时后才显现。日志分散在多个 TaskManager，没有简单的"断点调试"手段。SQL 层的错误信息有时不够明确，需要深入理解底层执行模型才能诊断。

## 兼容生态

Flink SQL 语法主体兼容 ANSI SQL，扩展了流式语义（WATERMARK、窗口 TVF、MATCH_RECOGNIZE）。通过 HiveCatalog 可以集成 Hive Metastore，读写 Hive 表。Flink CDC（Change Data Capture）生态支持从 MySQL、PostgreSQL、MongoDB 等数据库实时捕获变更并以 SQL 方式处理。

## 对引擎开发者的参考价值

- **流式 SQL 语义设计**：如何将"持续变化的数据流"映射到关系代数的"表"概念上？Flink 通过 Dynamic Table（动态表）理论给出了答案——流是表的 Changelog，表是流的快照。这一理论框架是流式 SQL 领域最重要的学术贡献。
- **Watermark 机制**：Watermark 解决了事件时间下的乱序和延迟问题，是流处理引擎的核心机制。Flink 的 Watermark 传播和对齐策略是这一领域的标杆实现。
- **Changelog 编码**：用 INSERT/UPDATE_BEFORE/UPDATE_AFTER/DELETE 四种消息编码关系操作的变更，使得流引擎可以在流上执行 GROUP BY 聚合并持续更新结果。这一设计被 Materialize、RisingWave 等新兴流数据库所借鉴。
- **State TTL**：为流式 Join 和聚合的状态设置过期时间（Time-To-Live），在正确性和资源消耗之间做权衡。这是流引擎独有的设计维度，TTL 配置策略值得深入研究。

---

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/flink.sql) | 流表二象性，WITH 子句指定 Connector(Kafka/JDBC/文件) |
| [改表](../ddl/alter-table/flink.sql) | ALTER TABLE 修改 Connector 属性，Schema 变更有限 |
| [索引](../ddl/indexes/flink.sql) | 无索引（流处理引擎），依赖底层存储 |
| [约束](../ddl/constraints/flink.sql) | PK 声明用于去重/JOIN 优化，NOT ENFORCED |
| [视图](../ddl/views/flink.sql) | TEMPORARY VIEW 流处理管道，无物化视图 |
| [序列与自增](../ddl/sequences/flink.sql) | 无 SEQUENCE/自增，事件时间/处理时间驱动 |
| [数据库/Schema/用户](../ddl/users-databases/flink.sql) | Catalog(Hive/JDBC)+Database 命名空间 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/flink.sql) | 无动态 SQL，SQL Client/Gateway 提交作业 |
| [错误处理](../advanced/error-handling/flink.sql) | 无过程式错误处理，作业级容错(Checkpoint/Savepoint) |
| [执行计划](../advanced/explain/flink.sql) | EXPLAIN 展示流处理算子拓扑，State 管理 |
| [锁机制](../advanced/locking/flink.sql) | 无锁（流处理引擎），Exactly-Once 语义靠 Checkpoint |
| [分区](../advanced/partitioning/flink.sql) | PARTITION BY 用于时间窗口分区，非传统分区 |
| [权限](../advanced/permissions/flink.sql) | 无内置权限，依赖外部 Catalog 安全 |
| [存储过程](../advanced/stored-procedures/flink.sql) | 无存储过程（流处理引擎定位） |
| [临时表](../advanced/temp-tables/flink.sql) | CREATE TEMPORARY TABLE 定义流/批数据源 |
| [事务](../advanced/transactions/flink.sql) | Exactly-Once 语义(Two-Phase Commit)，非传统 ACID |
| [触发器](../advanced/triggers/flink.sql) | 无触发器，流处理本身即事件驱动 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/flink.sql) | 不支持传统 DELETE（流处理引擎），Retract 流撤回 |
| [插入](../dml/insert/flink.sql) | INSERT INTO 持续写入 Sink，流式语义 |
| [更新](../dml/update/flink.sql) | 不支持传统 UPDATE，Retract/Upsert 流语义替代 |
| [Upsert](../dml/upsert/flink.sql) | Upsert Sink 按 PK 更新，非标准 MERGE |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/flink.sql) | TUMBLE/HOP/SESSION 窗口聚合（流处理独有） |
| [条件函数](../functions/conditional/flink.sql) | IF/CASE/COALESCE 标准 |
| [日期函数](../functions/date-functions/flink.sql) | CURRENT_TIMESTAMP/PROCTIME/ROWTIME 流处理时间语义 |
| [数学函数](../functions/math-functions/flink.sql) | 基础数学函数 |
| [字符串函数](../functions/string-functions/flink.sql) | CONCAT/SUBSTR/REGEXP 标准 |
| [类型转换](../functions/type-conversion/flink.sql) | CAST/TRY_CAST 标准 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/flink.sql) | WITH 标准支持，用于简化流查询 |
| [全文搜索](../query/full-text-search/flink.sql) | 无全文搜索（流处理引擎） |
| [连接查询](../query/joins/flink.sql) | Regular/Interval/Temporal/Lookup JOIN（流处理特有） |
| [分页](../query/pagination/flink.sql) | 不适用（流处理无分页概念），批模式支持 LIMIT |
| [行列转换](../query/pivot-unpivot/flink.sql) | 无原生 PIVOT，CASE+GROUP BY 或 JSON 函数 |
| [集合操作](../query/set-operations/flink.sql) | UNION ALL(流合并)，INTERSECT/EXCEPT(批模式) |
| [子查询](../query/subquery/flink.sql) | IN/EXISTS 子查询，流处理下有限支持 |
| [窗口函数](../query/window-functions/flink.sql) | OVER 窗口+TVF 窗口(TUMBLE/HOP/SESSION/CUMULATE) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/flink.sql) | 不适用（流处理场景），批模式可用 VALUES 构造 |
| [去重](../scenarios/deduplication/flink.sql) | ROW_NUMBER=1 流式去重（State 自动管理） |
| [区间检测](../scenarios/gap-detection/flink.sql) | Interval JOIN 检测时间区间 |
| [层级查询](../scenarios/hierarchical-query/flink.sql) | 不适用（流处理场景） |
| [JSON 展开](../scenarios/json-flatten/flink.sql) | JSON_VALUE/JSON_QUERY，CROSS JOIN UNNEST 展开 |
| [迁移速查](../scenarios/migration-cheatsheet/flink.sql) | 流批一体 SQL，WITH Connector 定义是核心，时间语义独特 |
| [TopN 查询](../scenarios/ranking-top-n/flink.sql) | ROW_NUMBER 流式 TopN（State 自动维护排名） |
| [累计求和](../scenarios/running-total/flink.sql) | CUMULATE 窗口或 SUM() OVER(ROWS UNBOUNDED PRECEDING) |
| [缓慢变化维](../scenarios/slowly-changing-dim/flink.sql) | Temporal JOIN 维表关联（流处理独有模式） |
| [字符串拆分](../scenarios/string-split-to-rows/flink.sql) | UNNEST+SPLIT 展开 |
| [窗口分析](../scenarios/window-analytics/flink.sql) | TVF 窗口(TUMBLE/HOP/SESSION/CUMULATE) 流处理独有 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/flink.sql) | ARRAY/MAP/ROW 原生支持，UNNEST 展开 |
| [日期时间](../types/datetime/flink.sql) | TIMESTAMP/TIMESTAMP_LTZ，事件时间/处理时间 Watermark |
| [JSON](../types/json/flink.sql) | JSON_VALUE/JSON_QUERY 路径查询，无 JSON 索引 |
| [数值类型](../types/numeric/flink.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/DECIMAL 标准 |
| [字符串类型](../types/string/flink.sql) | STRING/VARCHAR/CHAR 标准，UTF-8 |
