# BigQuery

**分类**: Google 云数仓
**文件数**: 51 个 SQL 文件
**总行数**: 6290 行

## 概述与定位

BigQuery 是 Google Cloud 提供的无服务器（Serverless）云数据仓库。用户无需管理服务器、索引或连接池，只需编写 SQL 即可分析 PB 级数据。其核心计费模型是**按扫描数据量付费**（on-demand）或按预留 Slot 付费（flat-rate），这一商业模式直接影响了 SQL 层的设计取舍——没有索引、没有手动调优旋钮，一切由平台透明管理。

BigQuery 的定位是"零运维分析"：将传统 DBA 的工作（分区规划、统计信息收集、查询计划调优）全部内化到引擎中，用户只关注 SQL 本身。这使得它特别适合数据分析师和数据科学家，但也意味着对习惯了 RDBMS 精细控制的工程师来说，可操作空间有限。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2010 | Google 发表 Dremel 论文，描述列式存储+树状调度的大规模查询架构 |
| 2011 | BigQuery 作为 Google Cloud 服务公开发布，初期仅支持类 SQL 方言（Legacy SQL） |
| 2016 | 引入**标准 SQL**（Standard SQL），语法向 ANSI SQL 靠拢，Legacy SQL 逐步弃用 |
| 2019 | BI Engine 发布，提供内存加速层；支持 BigQuery ML（在 SQL 中训练模型） |
| 2021 | BigQuery Omni 发布，支持在 AWS/Azure 上查询数据（多云架构） |
| 2023 | 持续增强：支持 SEARCH INDEX 全文索引、Apache Iceberg 外部表、向量搜索 |

## 核心设计思路

- **无服务器哲学**：没有实例、没有连接池、没有 VACUUM。用户提交 SQL，平台分配 Slot（计算单元）执行查询，完成后释放。这决定了 BigQuery 没有索引——因为索引是有状态的服务器端优化，与无服务器模型冲突。
- **列式存储 Capacitor**：底层存储格式 Capacitor 按列组织数据，支持嵌套结构（STRUCT/ARRAY），这是 Dremel 论文的核心思想。列式存储使得 `SELECT a, b FROM t` 只扫描两列而非整行，直接降低按扫描量计费的成本。
- **Slot 执行模型**：查询被拆分为多个 Stage，每个 Stage 由多个 Slot 并行执行。Slot 是 CPU + 内存 + I/O 的封装单元。用户无法控制 Slot 分配策略，但可以通过预留（Reservation）保证并发。
- **STRUCT/ARRAY 一等公民**：BigQuery 原生支持嵌套数据结构，不需要 JSON 序列化。`STRUCT<name STRING, age INT64>` 是正式的列类型，查询时可以直接 `t.address.city` 点号访问。这一设计源于 Google 内部 Protocol Buffers 的数据模型传统。

## 独特特色

- **按扫描量计费**：on-demand 模式下每 TB 扫描约 $5-$6.25，这使得 `SELECT *` 成为最昂贵的反模式。用户必须养成只选必要列的习惯——计费模型直接塑造了 SQL 编写风格。
- **INT64/STRING 类型命名**：不使用 INTEGER/VARCHAR，而是 INT64、FLOAT64、STRING、BOOL，命名风格来自 Google 内部类型系统，与标准 SQL 的 INTEGER/DECIMAL 不同。
- **SAFE_ 前缀函数**：`SAFE_DIVIDE(a, b)` 在除零时返回 NULL 而非报错；几乎所有函数都有 SAFE_ 版本。这是 BigQuery 独有的安全函数设计，避免了分析查询因脏数据中断。
- **分区 + 聚集代替索引**：通过 `PARTITION BY date_col` 和 `CLUSTER BY col1, col2` 实现数据裁剪，这是 BigQuery 唯一的物理优化手段。分区裁剪减少扫描量（省钱），聚集排序加速过滤（省时间）。
- **约束 NOT ENFORCED**：BigQuery 支持 PRIMARY KEY / FOREIGN KEY 声明，但标注 `NOT ENFORCED`——仅作为元数据提示供优化器使用，不实际校验数据。这是无服务器架构下的妥协：强制约束需要事务性写入，与高吞吐 INSERT 冲突。
- **TABLE_SUFFIX 通配符表**：`SELECT * FROM project.dataset.events_*` 配合 `_TABLE_SUFFIX` 可以跨多表查询，这是 BigQuery 处理按日分表（日期后缀）的独特方式。
- **GENERATE_UUID()**：内置 UUID 生成函数，在无自增列的环境下提供唯一标识符。

## 已知的设计不足与历史包袱

- **DML 并发限制**：同一表的 UPDATE/DELETE/MERGE 操作受严格的并发配额限制（每表每天上千次级别），不适合高频小事务写入。BigQuery 本质是分析引擎，不是 OLTP 数据库。
- **无自增列**：没有 AUTO_INCREMENT 或 SERIAL，需要用 `GENERATE_UUID()` 或 `ROW_NUMBER()` 模拟。
- **无索引**：唯一的物理优化是分区和聚集，无法为特定查询模式创建 B-Tree 或 Hash 索引。
- **约束不执行**：PK/FK 仅作元数据提示，不保证数据完整性，应用层必须自行保证。
- **Scripting 有限**：虽然支持 BEGIN...END 脚本块和存储过程，但功能远不及 PL/pgSQL 或 T-SQL，缺乏游标、包（Package）等高级特性。
- **无触发器**：无法在数据变更时自动执行逻辑，需要借助外部服务（Cloud Functions、Pub/Sub）实现类似功能。
- **STRUCT 嵌套字段不可直接 UPDATE**：不能 `UPDATE t SET t.address.city = 'X'`，必须整体替换整个 STRUCT 值。

## 兼容生态

BigQuery 标准 SQL 语法自成一体，与 PostgreSQL/MySQL 不兼容。但其 INFORMATION_SCHEMA 设计借鉴了 ANSI 标准，支持 ODBC/JDBC 连接。生态集成主要通过 Google Cloud 平台（Dataflow、Dataproc、Looker、Vertex AI）。

## 对引擎开发者的参考价值

- **Dremel 列式执行**：树状调度架构（Root Server → Intermediate → Leaf）是分布式查询引擎的经典参考，论文影响了 Apache Drill、Impala 等多个开源项目。
- **Capacitor 存储格式**：支持嵌套结构的列式存储设计，证明了不必将嵌套数据扁平化即可高效查询，这一思路后来被 Parquet/ORC 的嵌套支持所借鉴。
- **Slot-based 计费模型**：将计算资源量化为 Slot 并按使用付费，是云数仓商业模式的重要创新。这一模型要求引擎内部能精确度量每个查询的资源消耗。

---

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [bigquery.sql](../ddl/create-table/bigquery.sql) |
| 改表 | [bigquery.sql](../ddl/alter-table/bigquery.sql) |
| 索引 | [bigquery.sql](../ddl/indexes/bigquery.sql) |
| 约束 | [bigquery.sql](../ddl/constraints/bigquery.sql) |
| 视图 | [bigquery.sql](../ddl/views/bigquery.sql) |
| 序列与自增 | [bigquery.sql](../ddl/sequences/bigquery.sql) |
| 数据库/Schema/用户 | [bigquery.sql](../ddl/users-databases/bigquery.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [bigquery.sql](../advanced/dynamic-sql/bigquery.sql) |
| 错误处理 | [bigquery.sql](../advanced/error-handling/bigquery.sql) |
| 执行计划 | [bigquery.sql](../advanced/explain/bigquery.sql) |
| 锁机制 | [bigquery.sql](../advanced/locking/bigquery.sql) |
| 分区 | [bigquery.sql](../advanced/partitioning/bigquery.sql) |
| 权限 | [bigquery.sql](../advanced/permissions/bigquery.sql) |
| 存储过程 | [bigquery.sql](../advanced/stored-procedures/bigquery.sql) |
| 临时表 | [bigquery.sql](../advanced/temp-tables/bigquery.sql) |
| 事务 | [bigquery.sql](../advanced/transactions/bigquery.sql) |
| 触发器 | [bigquery.sql](../advanced/triggers/bigquery.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [bigquery.sql](../dml/delete/bigquery.sql) |
| 插入 | [bigquery.sql](../dml/insert/bigquery.sql) |
| 更新 | [bigquery.sql](../dml/update/bigquery.sql) |
| Upsert | [bigquery.sql](../dml/upsert/bigquery.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [bigquery.sql](../functions/aggregate/bigquery.sql) |
| 条件函数 | [bigquery.sql](../functions/conditional/bigquery.sql) |
| 日期函数 | [bigquery.sql](../functions/date-functions/bigquery.sql) |
| 数学函数 | [bigquery.sql](../functions/math-functions/bigquery.sql) |
| 字符串函数 | [bigquery.sql](../functions/string-functions/bigquery.sql) |
| 类型转换 | [bigquery.sql](../functions/type-conversion/bigquery.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [bigquery.sql](../query/cte/bigquery.sql) |
| 全文搜索 | [bigquery.sql](../query/full-text-search/bigquery.sql) |
| 连接查询 | [bigquery.sql](../query/joins/bigquery.sql) |
| 分页 | [bigquery.sql](../query/pagination/bigquery.sql) |
| 行列转换 | [bigquery.sql](../query/pivot-unpivot/bigquery.sql) |
| 集合操作 | [bigquery.sql](../query/set-operations/bigquery.sql) |
| 子查询 | [bigquery.sql](../query/subquery/bigquery.sql) |
| 窗口函数 | [bigquery.sql](../query/window-functions/bigquery.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [bigquery.sql](../scenarios/date-series-fill/bigquery.sql) |
| 去重 | [bigquery.sql](../scenarios/deduplication/bigquery.sql) |
| 区间检测 | [bigquery.sql](../scenarios/gap-detection/bigquery.sql) |
| 层级查询 | [bigquery.sql](../scenarios/hierarchical-query/bigquery.sql) |
| JSON 展开 | [bigquery.sql](../scenarios/json-flatten/bigquery.sql) |
| 迁移速查 | [bigquery.sql](../scenarios/migration-cheatsheet/bigquery.sql) |
| TopN 查询 | [bigquery.sql](../scenarios/ranking-top-n/bigquery.sql) |
| 累计求和 | [bigquery.sql](../scenarios/running-total/bigquery.sql) |
| 缓慢变化维 | [bigquery.sql](../scenarios/slowly-changing-dim/bigquery.sql) |
| 字符串拆分 | [bigquery.sql](../scenarios/string-split-to-rows/bigquery.sql) |
| 窗口分析 | [bigquery.sql](../scenarios/window-analytics/bigquery.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [bigquery.sql](../types/array-map-struct/bigquery.sql) |
| 日期时间 | [bigquery.sql](../types/datetime/bigquery.sql) |
| JSON | [bigquery.sql](../types/json/bigquery.sql) |
| 数值类型 | [bigquery.sql](../types/numeric/bigquery.sql) |
| 字符串类型 | [bigquery.sql](../types/string/bigquery.sql) |
