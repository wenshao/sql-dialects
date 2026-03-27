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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/bigquery.sql) | 无服务器无索引，PARTITION+CLUSTER 替代，约束 NOT ENFORCED |
| [改表](../ddl/alter-table/bigquery.sql) | ALTER 支持有限，无 MODIFY COLUMN TYPE，Schema 演进受限 |
| [索引](../ddl/indexes/bigquery.sql) | 无传统索引，SEARCH INDEX 全文索引(2023+)，靠分区裁剪 |
| [约束](../ddl/constraints/bigquery.sql) | PK/FK NOT ENFORCED 仅元数据提示，不实际校验 |
| [视图](../ddl/views/bigquery.sql) | 物化视图自动刷新+智能调优，Authorized View 数据共享 |
| [序列与自增](../ddl/sequences/bigquery.sql) | 无自增列，GENERATE_UUID() 或 ROW_NUMBER 模拟 |
| [数据库/Schema/用户](../ddl/users-databases/bigquery.sql) | Dataset=Schema，IAM 权限管理，项目级隔离 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/bigquery.sql) | EXECUTE IMMEDIATE 脚本模式，Scripting(2019+) |
| [错误处理](../advanced/error-handling/bigquery.sql) | BEGIN...EXCEPTION 脚本级错误处理，功能有限 |
| [执行计划](../advanced/explain/bigquery.sql) | Execution Details 面板，Slot 消耗分析，无传统 EXPLAIN |
| [锁机制](../advanced/locking/bigquery.sql) | 无用户可见锁，DML 配额限制并发，乐观并发 |
| [分区](../advanced/partitioning/bigquery.sql) | PARTITION BY 日期/整数范围/时间戳，分区裁剪省钱关键 |
| [权限](../advanced/permissions/bigquery.sql) | IAM+Dataset/Table/Column 级别权限，Authorized View/Dataset |
| [存储过程](../advanced/stored-procedures/bigquery.sql) | JavaScript/SQL 存储过程，功能弱于 PL/pgSQL |
| [临时表](../advanced/temp-tables/bigquery.sql) | CREATE TEMP TABLE 会话级，_SESSION 前缀引用 |
| [事务](../advanced/transactions/bigquery.sql) | 多语句事务(2020+)，DML 并发配额限制，非 OLTP |
| [触发器](../advanced/triggers/bigquery.sql) | 无触发器，借助 Cloud Functions/Pub/Sub 实现 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/bigquery.sql) | DELETE+WHERE 必须，DML 配额限制，分区删除高效 |
| [插入](../dml/insert/bigquery.sql) | INSERT+SELECT 为主，流式插入 API，LOAD 批量导入 |
| [更新](../dml/update/bigquery.sql) | UPDATE+WHERE 必须，STRUCT 嵌套字段不可直接更新 |
| [Upsert](../dml/upsert/bigquery.sql) | MERGE 标准语法，DML 配额限制写入频率 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/bigquery.sql) | APPROX_COUNT_DISTINCT 近似聚合，ARRAY_AGG 嵌套 |
| [条件函数](../functions/conditional/bigquery.sql) | IF/IIF/CASE/COALESCE，SAFE_ 前缀安全函数独有 |
| [日期函数](../functions/date-functions/bigquery.sql) | DATE/DATETIME/TIMESTAMP 三类型，DATE_TRUNC，EXTRACT 标准 |
| [数学函数](../functions/math-functions/bigquery.sql) | SAFE_DIVIDE 除零安全，IEEE_DIVIDE，GREATEST/LEAST 内置 |
| [字符串函数](../functions/string-functions/bigquery.sql) | REGEXP_EXTRACT/REPLACE，FORMAT，SPLIT 返回 ARRAY |
| [类型转换](../functions/type-conversion/bigquery.sql) | SAFE_CAST 安全转换（类似 TRY_CAST），CAST 标准 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/bigquery.sql) | WITH 标准支持，递归 CTE 支持，自动优化 |
| [全文搜索](../query/full-text-search/bigquery.sql) | SEARCH INDEX(2023+) 全文索引，SEARCH 函数，LOG-based |
| [连接查询](../query/joins/bigquery.sql) | JOIN 标准完整，CROSS JOIN UNNEST 展开数组，无 LATERAL 关键字 |
| [分页](../query/pagination/bigquery.sql) | LIMIT/OFFSET，无 FETCH FIRST，大结果集建议导出 |
| [行列转换](../query/pivot-unpivot/bigquery.sql) | PIVOT/UNPIVOT 原生支持 |
| [集合操作](../query/set-operations/bigquery.sql) | UNION/INTERSECT/EXCEPT+ALL/DISTINCT 完整 |
| [子查询](../query/subquery/bigquery.sql) | 关联子查询+IN/EXISTS，标量子查询优化好 |
| [窗口函数](../query/window-functions/bigquery.sql) | 完整窗口函数，QUALIFY 过滤独有（无需嵌套） |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/bigquery.sql) | GENERATE_DATE_ARRAY+UNNEST 生成日期序列 |
| [去重](../scenarios/deduplication/bigquery.sql) | ROW_NUMBER+QUALIFY 最简写法（无需子查询） |
| [区间检测](../scenarios/gap-detection/bigquery.sql) | 窗口函数+GENERATE_DATE_ARRAY 检测间隙 |
| [层级查询](../scenarios/hierarchical-query/bigquery.sql) | 递归 CTE 支持，迭代深度有限制 |
| [JSON 展开](../scenarios/json-flatten/bigquery.sql) | JSON_EXTRACT+UNNEST，JSON_QUERY_ARRAY 展开 |
| [迁移速查](../scenarios/migration-cheatsheet/bigquery.sql) | INT64/STRING 类型命名差异，无索引，DML 配额限制 |
| [TopN 查询](../scenarios/ranking-top-n/bigquery.sql) | QUALIFY ROW_NUMBER() 最简写法，无需子查询 |
| [累计求和](../scenarios/running-total/bigquery.sql) | SUM() OVER 标准，大数据量下 Slot 自动扩展 |
| [缓慢变化维](../scenarios/slowly-changing-dim/bigquery.sql) | MERGE 标准，快照表+时间旅行(7天) 辅助 |
| [字符串拆分](../scenarios/string-split-to-rows/bigquery.sql) | SPLIT 返回 ARRAY+UNNEST 展开，原生简洁 |
| [窗口分析](../scenarios/window-analytics/bigquery.sql) | 完整窗口函数+QUALIFY（最简过滤），WINDOW 命名子句 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/bigquery.sql) | ARRAY/STRUCT 一等公民（Dremel 传统），嵌套查询自然 |
| [日期时间](../types/datetime/bigquery.sql) | DATE/TIME/DATETIME/TIMESTAMP 四类型，时区处理清晰 |
| [JSON](../types/json/bigquery.sql) | JSON 类型(2022+)，JSON_EXTRACT 路径查询，无 JSON 索引 |
| [数值类型](../types/numeric/bigquery.sql) | INT64/FLOAT64/NUMERIC/BIGNUMERIC，命名非标准但清晰 |
| [字符串类型](../types/string/bigquery.sql) | STRING 无长度限制，BYTES 二进制，REGEXP 内置 |
