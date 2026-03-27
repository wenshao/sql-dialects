# Hologres

**分类**: 阿里云实时数仓
**文件数**: 51 个 SQL 文件
**总行数**: 4482 行

## 概述与定位

Hologres 是阿里云自主研发的实时交互式分析引擎，兼容 PostgreSQL 协议和生态。它定位于"实时数仓"——在同一引擎中同时支持实时写入（毫秒级延迟）和复杂分析查询（亚秒级响应），消除传统架构中实时层（如 Flink + HBase/Redis）与离线层（如 MaxCompute/Hive）之间的数据搬运。Hologres 与 MaxCompute 深度集成，可直接加速查询 MaxCompute 离线表。

## 历史与演进

- **2018 年**：阿里巴巴内部启动 Hologres 项目，目标是解决实时分析场景下的高并发低延迟问题。
- **2020 年**：Hologres 作为阿里云公共云服务正式发布（GA），支持 PostgreSQL 11 兼容。
- **2021 年**：引入行列混存引擎、Binlog 变更捕获、与 Flink 的深度集成（实时写入）。
- **2022 年**：增强向量化执行引擎、自动物化视图、分区表增强。
- **2023 年**：引入 Serverless 计算模式、增强 JSON/半结构化数据处理、MaxCompute 外部表加速。
- **2024-2025 年**：增强存算分离架构、向量索引（AI 向量搜索）、增强与 Flink CDC 的集成。

## 核心设计思路

1. **PostgreSQL 兼容**：使用标准 PostgreSQL 客户端（psql、JDBC/ODBC）即可连接，大部分 PostgreSQL 生态工具可直接使用。
2. **行列混存**：通过 `set_table_property` 设置表的存储类型——`column`（列存，适合分析）、`row`（行存，适合点查）、`row,column`（行列混存，兼顾二者）。
3. **实时写入 + 实时查询**：写入通过 Fixed Plan 优化，毫秒级可见；查询通过向量化执行和列存加速实现亚秒级响应。
4. **MaxCompute 加速**：可直接创建 MaxCompute 外部表，通过 Hologres 引擎加速查询 MaxCompute 中的离线数据。

## 独特特色

| 特性 | 说明 |
|---|---|
| **set_table_property** | 通过 `CALL set_table_property('t', 'orientation', 'column')` 设置表的存储格式、分布键、聚簇键等物理属性。 |
| **行列混存** | 同一张表可同时维护行存和列存副本，点查走行存，分析扫描走列存，引擎自动选择。 |
| **Binlog 实时消费** | 表变更自动生成 Binlog，下游 Flink/Spark 可实时消费变更数据，构建实时数据管道。 |
| **MaxCompute 外部表** | 通过外部表映射直接查询 MaxCompute 表数据，利用 Hologres 的向量化引擎加速 MaxCompute 的离线分析。 |
| **Distribution Key** | `CALL set_table_property('t', 'distribution_key', 'col')` 指定数据分布键，等值查询和 JOIN 可利用本地化避免 Shuffle。 |
| **Clustering Key** | 数据在存储中按 Clustering Key 排序存储，范围查询可利用物理排序高效过滤。 |
| **Segment Key** | 文件级分段键，基于时间列实现文件级剪枝，适合时序数据场景。 |

## 已知不足

- **阿里云专有**：Hologres 仅在阿里云上可用，无法在其他云平台或本地部署。
- **PostgreSQL 兼容度不完全**：虽然兼容 PG 协议，但不支持 PG 的部分高级功能（自定义类型、扩展、物化视图的完整语义等）。
- **文档偏少**：相比 PostgreSQL/MySQL 等主流数据库，Hologres 的技术文档和社区讨论资料较少，尤其是英文资料。
- **成本较高**：实时数仓的计算和存储资源费用较高，需仔细规划实例规格和数据生命周期。
- **学习曲线**：set_table_property 的配置项较多（orientation、distribution_key、clustering_key、segment_key、bitmap_columns 等），需要理解存储层设计才能优化性能。

## 对引擎开发者的参考价值

- **行列混存引擎设计**：在同一张表上同时维护行存索引（点查优化）和列存文件（扫描优化），自动路由查询到最优存储路径，对 HTAP 引擎有核心参考。
- **set_table_property 模型**：通过函数调用而非 DDL 语法设置物理属性的设计，比在 CREATE TABLE 中堆砌关键字更灵活，对存储属性管理有借鉴。
- **Fixed Plan 写入优化**：对已知模式的 INSERT 语句跳过优化器直接生成固定执行计划，将写入延迟降到毫秒级，对高频写入引擎有参考。
- **Binlog 集成**：将变更数据捕获作为引擎内置能力而非外部组件，对数据库与流处理集成有参考。
- **外部表加速查询**：通过本地向量化引擎加速查询远端数据源的模式，对联邦查询引擎的性能优化有借鉴。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/hologres.sql) | PG 兼容(阿里云 HSAP)，行存/列存/行列混存可选 |
| [改表](../ddl/alter-table/hologres.sql) | ALTER(PG 兼容)，在线变更 |
| [索引](../ddl/indexes/hologres.sql) | Clustering Key/Segment Key/Bitmap/Dictionary 编码(独有) |
| [约束](../ddl/constraints/hologres.sql) | PK 执行(行存表)，其他约束有限 |
| [视图](../ddl/views/hologres.sql) | 普通视图(PG 兼容)，外部表(MaxCompute 联邦) |
| [序列与自增](../ddl/sequences/hologres.sql) | SERIAL(PG 兼容)，分布式自增 |
| [数据库/Schema/用户](../ddl/users-databases/hologres.sql) | PG 兼容权限，实例级隔离 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/hologres.sql) | EXECUTE(PG 兼容，有限) |
| [错误处理](../advanced/error-handling/hologres.sql) | PG 兼容异常处理(有限) |
| [执行计划](../advanced/explain/hologres.sql) | EXPLAIN ANALYZE(PG 兼容)，HQE/SQE 双引擎 |
| [锁机制](../advanced/locking/hologres.sql) | 无行级锁(列存 OLAP)，行存表支持行锁 |
| [分区](../advanced/partitioning/hologres.sql) | 分区表(PG 兼容)，Segment Key 数据分布 |
| [权限](../advanced/permissions/hologres.sql) | PG 兼容 RBAC，RAM 云权限集成 |
| [存储过程](../advanced/stored-procedures/hologres.sql) | PG 兼容(有限支持) |
| [临时表](../advanced/temp-tables/hologres.sql) | TEMPORARY TABLE(PG 兼容) |
| [事务](../advanced/transactions/hologres.sql) | 行存表 ACID 事务，列存表最终一致性 |
| [触发器](../advanced/triggers/hologres.sql) | 不支持触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/hologres.sql) | DELETE(PG 兼容)，行存实时/列存批量 |
| [插入](../dml/insert/hologres.sql) | INSERT(PG 兼容)，Fixed Plan 加速点查写入 |
| [更新](../dml/update/hologres.sql) | UPDATE(PG 兼容)，行存实时更新 |
| [Upsert](../dml/upsert/hologres.sql) | INSERT ON CONFLICT(PG 兼容)，行存表高频 Upsert |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/hologres.sql) | PG 兼容聚合，列存向量化加速 |
| [条件函数](../functions/conditional/hologres.sql) | CASE/COALESCE(PG 兼容) |
| [日期函数](../functions/date-functions/hologres.sql) | PG 兼容日期函数 |
| [数学函数](../functions/math-functions/hologres.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/hologres.sql) | PG 兼容字符串函数 |
| [类型转换](../functions/type-conversion/hologres.sql) | CAST/::(PG 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/hologres.sql) | WITH+递归 CTE(PG 兼容) |
| [全文搜索](../query/full-text-search/hologres.sql) | GIN 索引全文检索(PG 兼容，有限) |
| [连接查询](../query/joins/hologres.sql) | Hash/Nested Loop JOIN(PG 兼容)，Shuffle 分布式 |
| [分页](../query/pagination/hologres.sql) | LIMIT/OFFSET(PG 兼容) |
| [行列转换](../query/pivot-unpivot/hologres.sql) | 无原生 PIVOT(PG 兼容) |
| [集合操作](../query/set-operations/hologres.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/hologres.sql) | 关联子查询(PG 兼容) |
| [窗口函数](../query/window-functions/hologres.sql) | 完整窗口函数(PG 兼容)，向量化加速 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/hologres.sql) | generate_series(PG 兼容) |
| [去重](../scenarios/deduplication/hologres.sql) | ROW_NUMBER+CTE(PG 兼容) |
| [区间检测](../scenarios/gap-detection/hologres.sql) | 窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/hologres.sql) | 递归 CTE(PG 兼容) |
| [JSON 展开](../scenarios/json-flatten/hologres.sql) | json_each/json_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/hologres.sql) | PG 兼容+行列混存+MaxCompute 联邦是核心特色 |
| [TopN 查询](../scenarios/ranking-top-n/hologres.sql) | ROW_NUMBER+LIMIT(PG 兼容) |
| [累计求和](../scenarios/running-total/hologres.sql) | SUM() OVER(PG 兼容)，向量化加速 |
| [缓慢变化维](../scenarios/slowly-changing-dim/hologres.sql) | INSERT ON CONFLICT(PG 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/hologres.sql) | string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/hologres.sql) | 完整窗口函数(PG 兼容)，HSAP 混合分析 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/hologres.sql) | ARRAY(PG 兼容)，无 STRUCT |
| [日期时间](../types/datetime/hologres.sql) | DATE/TIMESTAMP/TIMESTAMPTZ(PG 兼容) |
| [JSON](../types/json/hologres.sql) | JSON/JSONB(PG 兼容)，GIN 索引 |
| [数值类型](../types/numeric/hologres.sql) | INT/BIGINT/NUMERIC/FLOAT(PG 兼容) |
| [字符串类型](../types/string/hologres.sql) | TEXT/VARCHAR(PG 兼容) |
