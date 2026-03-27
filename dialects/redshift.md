# Amazon Redshift

**分类**: AWS 云数仓（基于 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4862 行

## 概述与定位

Amazon Redshift 是 AWS 推出的全托管云数据仓库服务，基于 ParAccel（PostgreSQL 8.0.2 分叉）演化而来。它将 MPP（大规模并行处理）架构与列式存储相结合，面向 PB 级数据的交互式分析查询。Redshift 是云数仓赛道的先行者（2012 年发布），凭借"按需付费 + 与 AWS 生态深度集成"的模式迅速成为最广泛使用的云数仓之一。

## 历史与演进

- **2012 年**：Redshift 正式发布（GA），基于 ParAccel 的列式 MPP 引擎，提供 PostgreSQL 8.x 兼容的 SQL 接口。
- **2015 年**：引入 Redshift Spectrum，支持直接查询 S3 上的数据而无需加载到集群本地。
- **2018 年**：引入弹性调整（Elastic Resize）、并发扩展（Concurrency Scaling）、结果集缓存。
- **2019 年**：发布 AQUA（Advanced Query Accelerator），在存储层嵌入硬件加速查询处理。
- **2020 年**：引入 RA3 节点类型，实现计算与存储分离（托管存储基于 S3）。
- **2021 年**：Redshift Serverless 发布，用户无需管理集群即可按查询量付费。
- **2022 年**：引入 SUPER 半结构化数据类型、多数仓数据共享（Data Sharing）。
- **2023-2025 年**：增强 MERGE 支持、增量物化视图刷新、零 ETL 集成（Aurora/DynamoDB 到 Redshift 自动复制）。

## 核心设计思路

1. **列式存储 + MPP**：数据按列存储并自动压缩，查询被分发到多个计算节点并行执行。
2. **分布键与排序键**：DISTKEY 控制数据在节点间的分布策略（减少数据倾斜和网络传输），SORTKEY 控制磁盘上的物理排序（加速范围扫描和 Zone Map 裁剪）。
3. **深度 AWS 集成**：COPY 命令从 S3/DynamoDB/EMR 批量加载数据，UNLOAD 导出到 S3，Spectrum 联邦查询 S3 数据湖。
4. **计算存储分离**：RA3 节点类型使用托管存储（Redshift Managed Storage），热数据缓存在本地 SSD，冷数据自动落到 S3。

## 独特特色

| 特性 | 说明 |
|---|---|
| **DISTKEY / SORTKEY** | 建表时指定 `DISTKEY(col)` 和 `SORTKEY(col1, col2)`，直接控制数据的物理分布和排序，是查询调优的核心手段。 |
| **COPY from S3** | 高吞吐批量加载命令，支持 CSV/JSON/Parquet/ORC 格式，自动并行从 S3 多个文件加载到多个切片。 |
| **SUPER 类型** | 半结构化数据类型，存储 JSON/数组/对象，支持 PartiQL 语法查询（如 `s.address.city`），无需预定义 schema。 |
| **Redshift Spectrum** | 在 SQL 中直接查询 S3 上的外部表（Parquet/ORC/CSV），与本地表 JOIN，实现数据湖与数仓的联邦查询。 |
| **Concurrency Scaling** | 查询并发超过集群能力时自动弹出临时集群处理溢出查询，用户无感知。 |
| **Zone Map** | 自动维护每个 1MB 磁盘块的 min/max 元数据，配合 SORTKEY 实现高效的块级过滤。 |
| **Data Sharing** | 多个 Redshift 集群/Serverless 实例之间实时共享数据，无需复制或 ETL。 |

## 已知不足

- **PostgreSQL 兼容性有限**：基于 PG 8.x 分叉，不支持 PG 的许多现代特性——无存储过程（仅 UDF）、无触发器、无 GIN/GiST 索引、无数组类型。
- **UPDATE/DELETE 开销大**：列式存储下行级更新代价高，频繁小批量写入性能差，需定期 VACUUM 回收空间。
- **主键/外键不强制**：约束仅作为优化器提示，不实际校验数据完整性，可能导致数据质量问题。
- **存储过程支持较晚**：2018 年才引入 PL/pgSQL 存储过程，功能仍不如原生 PostgreSQL 完备。
- **SORTKEY 选择困难**：Compound SORTKEY 只对前缀列有效，Interleaved SORTKEY 的 VACUUM 开销大，调优需仔细权衡。

## 对引擎开发者的参考价值

- **DISTKEY/SORTKEY 模型**：将数据分布和物理排序决策暴露为 DDL 语法，是分布式查询引擎设计中数据布局策略的经典实现。
- **Zone Map 过滤**：每个存储块自动维护列的 min/max，在查询时进行块级剪枝——实现简单但效果显著，值得任何列存引擎借鉴。
- **COPY 的并行加载架构**：将外部文件切分后并行加载到多个计算切片的 pipeline 设计，对批量导入优化有重要参考。
- **SUPER 类型与 PartiQL**：在列存引擎中支持半结构化数据的存储与查询，展示了严格 schema 与灵活 schema 的折中方案。
- **Concurrency Scaling 弹性模型**：查询溢出时自动启动临时计算资源的架构，对云原生数仓的弹性设计有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/redshift.sql) | PG 8.x 分叉，列式存储，DISTKEY/SORTKEY 决定数据分布 |
| [改表](../ddl/alter-table/redshift.sql) | ALTER 受限，ADD COLUMN 可以，MODIFY TYPE 限制多 |
| [索引](../ddl/indexes/redshift.sql) | 无传统索引，SORTKEY(COMPOUND/INTERLEAVED) 替代 |
| [约束](../ddl/constraints/redshift.sql) | PK/FK/UNIQUE 声明但不强制(仅优化器提示) |
| [视图](../ddl/views/redshift.sql) | 普通视图+LATE BINDING VIEW，物化视图(2019+) |
| [序列与自增](../ddl/sequences/redshift.sql) | IDENTITY 自增列，无 SEQUENCE 对象 |
| [数据库/Schema/用户](../ddl/users-databases/redshift.sql) | PG 兼容权限，Datashare 跨集群共享 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/redshift.sql) | 存储过程内 EXECUTE，PL/pgSQL 子集 |
| [错误处理](../advanced/error-handling/redshift.sql) | EXCEPTION WHEN(PG 子集)，RAISE EXCEPTION |
| [执行计划](../advanced/explain/redshift.sql) | EXPLAIN 文本+SVL 系统视图分析，分布式 Slice 信息 |
| [锁机制](../advanced/locking/redshift.sql) | 表级锁为主，MVCC 快照隔离，序列化隔离(默认) |
| [分区](../advanced/partitioning/redshift.sql) | 无原生分区，SORTKEY+DISTKEY 替代，Spectrum 外部分区 |
| [权限](../advanced/permissions/redshift.sql) | PG 兼容 GRANT/REVOKE，Datashare 跨集群安全共享 |
| [存储过程](../advanced/stored-procedures/redshift.sql) | PL/pgSQL 子集(2018+)，功能弱于 PostgreSQL |
| [临时表](../advanced/temp-tables/redshift.sql) | CREATE TEMP TABLE(PG 兼容)，会话级 |
| [事务](../advanced/transactions/redshift.sql) | 序列化隔离(默认)，ACID，自动提交 |
| [触发器](../advanced/triggers/redshift.sql) | 不支持触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/redshift.sql) | DELETE 标准，TRUNCATE 释放存储，DELETE 标记延迟回收 |
| [插入](../dml/insert/redshift.sql) | COPY 命令从 S3 批量加载(推荐)，INSERT 逐行较慢 |
| [更新](../dml/update/redshift.sql) | UPDATE 实为 DELETE+INSERT(列式存储特性)，性能开销大 |
| [Upsert](../dml/upsert/redshift.sql) | MERGE(2023+)，之前用 DELETE+INSERT 或 staging 表模拟 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/redshift.sql) | LISTAGG，APPROXIMATE COUNT(HLL)，MEDIAN |
| [条件函数](../functions/conditional/redshift.sql) | CASE/COALESCE/NULLIF/NVL/NVL2/DECODE(PG+Oracle 混合) |
| [日期函数](../functions/date-functions/redshift.sql) | DATEADD/DATEDIFF/DATE_TRUNC，GETDATE() 当前时间 |
| [数学函数](../functions/math-functions/redshift.sql) | 完整数学函数，APPROXIMATE PERCENTILE |
| [字符串函数](../functions/string-functions/redshift.sql) | || 拼接，REGEXP_REPLACE/SUBSTR(PG 兼容) |
| [类型转换](../functions/type-conversion/redshift.sql) | CAST/:: 运算符(PG 风格)，隐式转换较宽松 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/redshift.sql) | WITH 标准+递归 CTE，PG 兼容 |
| [全文搜索](../query/full-text-search/redshift.sql) | 无全文搜索，依赖 Elasticsearch/OpenSearch |
| [连接查询](../query/joins/redshift.sql) | Hash/Merge/Nested Loop JOIN，DISTKEY 优化 co-located JOIN |
| [分页](../query/pagination/redshift.sql) | LIMIT/OFFSET(PG 兼容) |
| [行列转换](../query/pivot-unpivot/redshift.sql) | 无原生 PIVOT，CASE+GROUP BY 模拟 |
| [集合操作](../query/set-operations/redshift.sql) | UNION/INTERSECT/EXCEPT 完整(PG 兼容) |
| [子查询](../query/subquery/redshift.sql) | 关联子查询支持，标量子查询 |
| [窗口函数](../query/window-functions/redshift.sql) | 完整窗口函数(PG 兼容)，WLM 查询队列管理 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/redshift.sql) | 递归 CTE 或数字表生成日期序列 |
| [去重](../scenarios/deduplication/redshift.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/redshift.sql) | 窗口函数检测间隙 |
| [层级查询](../scenarios/hierarchical-query/redshift.sql) | 递归 CTE(PG 兼容) |
| [JSON 展开](../scenarios/json-flatten/redshift.sql) | JSON_EXTRACT_PATH_TEXT，JSON_PARSE，SUPER 类型(半结构化) |
| [迁移速查](../scenarios/migration-cheatsheet/redshift.sql) | PG 8.x 子集，DISTKEY/SORTKEY 是核心概念，无索引 |
| [TopN 查询](../scenarios/ranking-top-n/redshift.sql) | ROW_NUMBER+窗口函数，LIMIT 直接 |
| [累计求和](../scenarios/running-total/redshift.sql) | SUM() OVER 标准，列式存储聚合高效 |
| [缓慢变化维](../scenarios/slowly-changing-dim/redshift.sql) | MERGE(2023+)，之前用 staging 表+DELETE+INSERT |
| [字符串拆分](../scenarios/string-split-to-rows/redshift.sql) | SPLIT_PART+递归 CTE 或数字表展开 |
| [窗口分析](../scenarios/window-analytics/redshift.sql) | 完整窗口函数(PG 兼容)，列式存储加速 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/redshift.sql) | SUPER 类型(半结构化)，无原生 ARRAY/STRUCT 列 |
| [日期时间](../types/datetime/redshift.sql) | DATE/TIMESTAMP/TIMESTAMPTZ，无 TIME 类型 |
| [JSON](../types/json/redshift.sql) | SUPER 类型(半结构化) + JSON_EXTRACT，PartiQL 查询 |
| [数值类型](../types/numeric/redshift.sql) | SMALLINT-BIGINT/REAL/DOUBLE/DECIMAL(38)，PG 兼容 |
| [字符串类型](../types/string/redshift.sql) | VARCHAR(65535) 默认，CHAR 定长，PG 兼容 |
