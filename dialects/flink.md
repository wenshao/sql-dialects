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

| 模块 | 链接 |
|---|---|
| 建表 | [flink.sql](../ddl/create-table/flink.sql) |
| 改表 | [flink.sql](../ddl/alter-table/flink.sql) |
| 索引 | [flink.sql](../ddl/indexes/flink.sql) |
| 约束 | [flink.sql](../ddl/constraints/flink.sql) |
| 视图 | [flink.sql](../ddl/views/flink.sql) |
| 序列与自增 | [flink.sql](../ddl/sequences/flink.sql) |
| 数据库/Schema/用户 | [flink.sql](../ddl/users-databases/flink.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [flink.sql](../advanced/dynamic-sql/flink.sql) |
| 错误处理 | [flink.sql](../advanced/error-handling/flink.sql) |
| 执行计划 | [flink.sql](../advanced/explain/flink.sql) |
| 锁机制 | [flink.sql](../advanced/locking/flink.sql) |
| 分区 | [flink.sql](../advanced/partitioning/flink.sql) |
| 权限 | [flink.sql](../advanced/permissions/flink.sql) |
| 存储过程 | [flink.sql](../advanced/stored-procedures/flink.sql) |
| 临时表 | [flink.sql](../advanced/temp-tables/flink.sql) |
| 事务 | [flink.sql](../advanced/transactions/flink.sql) |
| 触发器 | [flink.sql](../advanced/triggers/flink.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [flink.sql](../dml/delete/flink.sql) |
| 插入 | [flink.sql](../dml/insert/flink.sql) |
| 更新 | [flink.sql](../dml/update/flink.sql) |
| Upsert | [flink.sql](../dml/upsert/flink.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [flink.sql](../functions/aggregate/flink.sql) |
| 条件函数 | [flink.sql](../functions/conditional/flink.sql) |
| 日期函数 | [flink.sql](../functions/date-functions/flink.sql) |
| 数学函数 | [flink.sql](../functions/math-functions/flink.sql) |
| 字符串函数 | [flink.sql](../functions/string-functions/flink.sql) |
| 类型转换 | [flink.sql](../functions/type-conversion/flink.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [flink.sql](../query/cte/flink.sql) |
| 全文搜索 | [flink.sql](../query/full-text-search/flink.sql) |
| 连接查询 | [flink.sql](../query/joins/flink.sql) |
| 分页 | [flink.sql](../query/pagination/flink.sql) |
| 行列转换 | [flink.sql](../query/pivot-unpivot/flink.sql) |
| 集合操作 | [flink.sql](../query/set-operations/flink.sql) |
| 子查询 | [flink.sql](../query/subquery/flink.sql) |
| 窗口函数 | [flink.sql](../query/window-functions/flink.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [flink.sql](../scenarios/date-series-fill/flink.sql) |
| 去重 | [flink.sql](../scenarios/deduplication/flink.sql) |
| 区间检测 | [flink.sql](../scenarios/gap-detection/flink.sql) |
| 层级查询 | [flink.sql](../scenarios/hierarchical-query/flink.sql) |
| JSON 展开 | [flink.sql](../scenarios/json-flatten/flink.sql) |
| 迁移速查 | [flink.sql](../scenarios/migration-cheatsheet/flink.sql) |
| TopN 查询 | [flink.sql](../scenarios/ranking-top-n/flink.sql) |
| 累计求和 | [flink.sql](../scenarios/running-total/flink.sql) |
| 缓慢变化维 | [flink.sql](../scenarios/slowly-changing-dim/flink.sql) |
| 字符串拆分 | [flink.sql](../scenarios/string-split-to-rows/flink.sql) |
| 窗口分析 | [flink.sql](../scenarios/window-analytics/flink.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [flink.sql](../types/array-map-struct/flink.sql) |
| 日期时间 | [flink.sql](../types/datetime/flink.sql) |
| JSON | [flink.sql](../types/json/flink.sql) |
| 数值类型 | [flink.sql](../types/numeric/flink.sql) |
| 字符串类型 | [flink.sql](../types/string/flink.sql) |
