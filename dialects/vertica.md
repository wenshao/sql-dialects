# Vertica

**分类**: 列式分析数据库
**文件数**: 51 个 SQL 文件
**总行数**: 4692 行

## 概述与定位

Vertica 是由数据库领域传奇人物 Michael Stonebraker（图灵奖得主）联合创办的列式分析数据库，最初基于其学术项目 C-Store 的研究成果。Vertica 的核心理念是用 Projections（投影）完全替代传统索引：数据以排序后的列存副本形式存储，查询直接扫描最优的 Projection 而无需维护额外索引。现隶属于 OpenText（原 Micro Focus/HP），在电信、金融、广告技术等分析密集型行业有广泛部署。

## 历史与演进

- **2005 年**：Vertica Systems 成立，基于 C-Store 研究项目开发商用列式数据库。
- **2007 年**：Vertica 1.0 发布，以 Projections 为核心的列式存储 + MPP 架构。
- **2011 年**：被 HP 收购，整合到 HP Vertica Analytics Platform 产品线中。
- **2015 年**：引入 Flex Tables（schema-on-read 半结构化数据）、原生支持 Parquet/ORC 外部表。
- **2017 年**：Vertica 9.x 引入 Eon 模式（计算存储分离架构），数据持久化在 S3/HDFS/GCS。
- **2020 年**：增加机器学习库（ML 函数）、改进 Kafka 集成和流式数据摄取。
- **2023 年**：Vertica 23.x 引入 Vertica Accelerator（云全托管服务）、向量搜索、增强 JSON 处理。
- **2024-2025 年**：被 OpenText 收购后继续推进云原生和 AI/ML 集成。

## 核心设计思路

1. **Projections 替代索引**：数据以多个 Projection（排序+列存副本）形式存储，每个 Projection 可有不同的排序键和列组合，优化器自动选择最佳 Projection 响应查询。
2. **SEGMENTED BY**：数据通过 `SEGMENTED BY HASH(col) ALL NODES` 分布到集群各节点，支持 UNSEGMENTED（全复制）策略。
3. **WOS/ROS 架构**：写入先进入 Write Optimized Store（WOS，内存行存），后台 Moveout 将数据转为 Read Optimized Store（ROS，磁盘列存）。
4. **混合负载支持**：通过资源池（Resource Pools）实现 OLTP 级小查询和 OLAP 级大扫描的并发共存。

## 独特特色

| 特性 | 说明 |
|---|---|
| **Projections** | 替代传统索引的核心概念：每个 Projection 是表的一个排序列存副本，可覆盖不同的查询模式，数据库自动维护一致性。 |
| **SEGMENTED BY** | `SEGMENTED BY HASH(col) ALL NODES` 控制数据分片，`UNSEGMENTED ALL NODES` 实现小维表全复制。 |
| **Flex Tables** | Schema-on-read 的半结构化表，`CREATE FLEX TABLE` 后直接加载 JSON/CSV，通过 `MapKeys()` 等函数动态提取列。 |
| **Eon 模式** | 计算存储分离架构，数据存储在 S3/GCS/HDFS，计算节点无状态可弹性伸缩，支持子集群（Subclusters）隔离。 |
| **Tuple Mover** | 后台自动将 WOS 数据合并到 ROS、合并小 ROS 容器，类似 LSM-Tree 的 Compaction 但针对列存优化。 |
| **Database Designer** | 内置自动设计工具，基于查询负载和数据特征自动推荐最优的 Projection 组合。 |
| **原生分析函数** | 丰富的分析函数集（时间序列插值 `TIMESERIES`、模式匹配 `MATCH`、事件会话 `CONDITIONAL_TRUE_EVENT`）。 |

## 已知不足

- **许可成本高**：企业版按节点/TB 计费，成本较高；社区版有 1TB 和 3 节点限制。
- **Projection 管理复杂**：多个 Projection 的存储开销和维护成本随数据量增长显著增加，需要仔细权衡。
- **写入延迟**：虽有 WOS 缓冲，但列存转换（Moveout）过程会消耗资源，不适合高频小事务写入。
- **生态系统较窄**：与主流 BI 工具的集成良好，但 ORM、应用框架和中文社区支持有限。
- **DELETE 性能**：列存表的 DELETE 是逻辑标记删除，实际空间回收需 Mergeout，大规模删除后查询性能可能下降。

## 对引擎开发者的参考价值

- **Projections 模型**：用数据的物理排序副本替代索引的设计思路，彻底消除了索引维护开销和索引-表双重读取的问题，对列存引擎设计有深远影响。
- **WOS/ROS 写入路径**：先行存缓冲再列存持久化的两阶段写入模式，与 LSM-Tree 有异曲同工之处，对实时列存引擎的写入优化有直接参考。
- **Database Designer**：基于查询负载自动推荐物理设计的工具化思路，对自适应物理设计（Adaptive Physical Design）的研究有参考价值。
- **Eon 模式存算分离**：无状态计算节点 + 共享存储 + 子集群隔离的架构，是云原生列存数据库的参考范式。
- **Flex Tables 实现**：在列存引擎中支持 schema-on-read 的做法——通过 __raw__ 列存储原始数据并动态提取——对半结构化数据处理有启发。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/vertica.sql) | 列式存储 MPP，Projection 物理设计(独有)，K-Safety 容错 |
| [改表](../ddl/alter-table/vertica.sql) | ALTER 在线，Projection 需同步刷新 |
| [索引](../ddl/indexes/vertica.sql) | 无传统索引，Projection 排序替代，Flattened Table |
| [约束](../ddl/constraints/vertica.sql) | PK/FK/UNIQUE/CHECK 声明不强制(优化器提示) |
| [视图](../ddl/views/vertica.sql) | 普通视图，LIVE AGGREGATE Projection 替代物化视图 |
| [序列与自增](../ddl/sequences/vertica.sql) | AUTO_INCREMENT+SEQUENCE 标准 |
| [数据库/Schema/用户](../ddl/users-databases/vertica.sql) | Schema 命名空间，RBAC 权限 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/vertica.sql) | 存储过程内 EXECUTE，PL/vSQL 过程语言 |
| [错误处理](../advanced/error-handling/vertica.sql) | EXCEPTION WHEN(PL/vSQL)，RAISE EXCEPTION |
| [执行计划](../advanced/explain/vertica.sql) | EXPLAIN ANALYZE 带 Projection 和分布信息 |
| [锁机制](../advanced/locking/vertica.sql) | MVCC Snapshot Isolation，无行级锁（OLAP 优化） |
| [分区](../advanced/partitioning/vertica.sql) | PARTITION BY 表级分区+Projection 排序分区组合 |
| [权限](../advanced/permissions/vertica.sql) | RBAC，Schema 级权限，数据收集审计 |
| [存储过程](../advanced/stored-procedures/vertica.sql) | PL/vSQL 过程语言(PG 兼容)，EXTERNAL 多语言 |
| [临时表](../advanced/temp-tables/vertica.sql) | LOCAL/GLOBAL TEMPORARY TABLE，ON COMMIT PRESERVE/DELETE |
| [事务](../advanced/transactions/vertica.sql) | ACID，Snapshot Isolation，自动提交默认开启 |
| [触发器](../advanced/triggers/vertica.sql) | 不支持触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/vertica.sql) | DELETE 标记删除(列式)，PURGE 真正回收空间 |
| [插入](../dml/insert/vertica.sql) | COPY 批量加载(推荐)，INSERT 逐行较慢 |
| [更新](../dml/update/vertica.sql) | UPDATE = DELETE+INSERT(列式存储特性)，性能开销 |
| [Upsert](../dml/upsert/vertica.sql) | MERGE 标准实现 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/vertica.sql) | GROUPING SETS/CUBE/ROLLUP，APPROXIMATE COUNT(HLL) |
| [条件函数](../functions/conditional/vertica.sql) | CASE/COALESCE/NULLIF/NVL/DECODE 标准 |
| [日期函数](../functions/date-functions/vertica.sql) | DATE_TRUNC/TIMESTAMPADD/TIMESTAMPDIFF，INTERVAL 类型 |
| [数学函数](../functions/math-functions/vertica.sql) | 完整数学函数，APPROXIMATE MEDIAN/PERCENTILE |
| [字符串函数](../functions/string-functions/vertica.sql) | || 拼接，REGEXP_REPLACE/SUBSTR 标准 |
| [类型转换](../functions/type-conversion/vertica.sql) | CAST/:: 运算符(PG 风格)，TRY_CAST 支持 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/vertica.sql) | WITH 标准+递归 CTE |
| [全文搜索](../query/full-text-search/vertica.sql) | Text Search(内置)，STEM/TOKENIZE 函数 |
| [连接查询](../query/joins/vertica.sql) | Hash/Merge JOIN，Projection 排序优化 co-located JOIN |
| [分页](../query/pagination/vertica.sql) | LIMIT/OFFSET 标准 |
| [行列转换](../query/pivot-unpivot/vertica.sql) | 无原生 PIVOT，CASE+GROUP BY 模拟 |
| [集合操作](../query/set-operations/vertica.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/vertica.sql) | 关联子查询+标量子查询优化 |
| [窗口函数](../query/window-functions/vertica.sql) | 完整窗口函数，ROWS/RANGE 帧，分析查询优势 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/vertica.sql) | TIMESERIES 子句(独有) 原生填充时间序列 |
| [去重](../scenarios/deduplication/vertica.sql) | ROW_NUMBER+CTE 去重(OLAP 标准方式) |
| [区间检测](../scenarios/gap-detection/vertica.sql) | TIMESERIES+窗口函数 |
| [层级查询](../scenarios/hierarchical-query/vertica.sql) | 递归 CTE 标准 |
| [JSON 展开](../scenarios/json-flatten/vertica.sql) | MAPJSONEXTRACTOR/FJSONPARSER，Flex Table 无 Schema 导入 |
| [迁移速查](../scenarios/migration-cheatsheet/vertica.sql) | Projection 物理设计+列式存储+无触发器是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/vertica.sql) | ROW_NUMBER+LIMIT 标准 |
| [累计求和](../scenarios/running-total/vertica.sql) | SUM() OVER 标准，列式存储聚合高效 |
| [缓慢变化维](../scenarios/slowly-changing-dim/vertica.sql) | MERGE 标准实现 |
| [字符串拆分](../scenarios/string-split-to-rows/vertica.sql) | MAPDELIMITEDEXTRACTOR+Flex Table 或 REGEXP |
| [窗口分析](../scenarios/window-analytics/vertica.sql) | 完整窗口函数，分析查询是核心场景 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/vertica.sql) | ROW(复合类型)，ARRAY(10.0+)，Flex Table 半结构化 |
| [日期时间](../types/datetime/vertica.sql) | DATE/TIME/TIMESTAMP/TIMESTAMPTZ/INTERVAL 完整 |
| [JSON](../types/json/vertica.sql) | Flex Table 无 Schema JSON 导入，JSON 函数解析 |
| [数值类型](../types/numeric/vertica.sql) | INT/FLOAT/NUMERIC(1024位精度)，APPROXIMATE |
| [字符串类型](../types/string/vertica.sql) | VARCHAR(65000)/CHAR/LONG VARCHAR，UTF-8 默认 |
