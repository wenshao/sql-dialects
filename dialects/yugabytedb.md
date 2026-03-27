# YugabyteDB

**分类**: 分布式数据库（兼容 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4726 行

## 概述与定位

YugabyteDB 是 Yugabyte 公司于 2017 年开源的分布式 SQL 数据库，核心设计目标是提供与 PostgreSQL 完全兼容的分布式数据库体验。它采用 Google Spanner 的分布式架构理念，同时复用 PostgreSQL 的查询层代码实现高度 PG 兼容。YugabyteDB 定位于需要水平扩展、高可用和全球分布的 OLTP 应用，特别适合从单机 PostgreSQL 向分布式架构迁移的场景。

## 历史与演进

- **2016 年**：前 Facebook 和 Oracle 工程师创立 Yugabyte 公司。
- **2017 年**：YugabyteDB 开源，初期仅提供 Cassandra 兼容的 YCQL API。
- **2018 年**：引入 YSQL API，直接集成 PostgreSQL 查询层实现 SQL 兼容。
- **2019 年**：2.0 GA，YSQL 基于 PG 11 fork 实现全面 SQL 支持。
- **2021 年**：2.8+ 引入跨地域部署增强和读副本（Read Replica）。
- **2022 年**：升级到 PG 11.2 兼容层，增强 xCluster 异步复制。
- **2023-2024 年**：基于 PG 15 的查询层升级，增强连接管理和性能优化。
- **2025 年**：持续推进 PG 兼容性和 YugabyteDB Anywhere/Managed 云服务。

## 核心设计思路

YugabyteDB 采用两层架构：**YB-TServer**（Tablet Server）管理数据存储，**YB-Master** 管理元数据和集群协调。数据按表分成多个 **Tablet**（类似 Spanner 的 Split），每个 Tablet 通过 Raft 共识协议维护多副本。存储层使用 DocDB（基于 RocksDB 改造的文档存储引擎），支持 MVCC 和分布式事务。独特之处在于提供**双 API**：YSQL（兼容 PostgreSQL）和 YCQL（兼容 Cassandra Query Language），共享同一底层存储引擎。

## 独特特色

- **YSQL/YCQL 双 API**：同一集群通过不同端口同时提供 PostgreSQL 兼容和 Cassandra 兼容接口。
- **哈希分片 + Range 分片**：默认使用哈希分片均匀分布数据，也支持 Range 分片用于范围查询优化。
- **Tablet 分裂与合并**：数据增长时 Tablet 自动分裂，支持手动和自动触发。
- **高度 PG 兼容**：直接复用 PostgreSQL 查询层代码，支持 PG 扩展、存储过程、触发器。
- **Colocated Tables**：`CREATE DATABASE ... WITH COLOCATED = true` 将小表共置于单一 Tablet 减少开销。
- **xCluster 复制**：跨集群异步复制用于异地灾备和读扩展。
- **地理分区**：`TABLESPACE` 机制控制数据的地域放置。

## 已知不足

- 哈希分片默认策略下范围查询（如 `BETWEEN`、`ORDER BY` 主键）性能不如 Range 分片。
- 与 PostgreSQL 的兼容虽高但并非 100%，部分扩展和高级特性可能不支持。
- YCQL API 功能更新速度慢于 YSQL，部分用户反馈 YCQL 的定位逐渐模糊。
- 分布式事务在高冲突场景下延迟高于单机 PostgreSQL。
- 集群最小部署需要 3 节点，对小规模应用有一定门槛。
- 全局二级索引在分布式场景下的性能开销需要关注。

## 对引擎开发者的参考价值

YugabyteDB 展示了如何通过 fork PostgreSQL 查询层快速获得 SQL 兼容性，同时将存储引擎替换为分布式方案的工程策略。其双 API 设计（SQL + NoSQL 共享存储）是多模数据库架构的有益探索。Tablet 的哈希 vs Range 分片选择、Colocated Tables 的小表优化策略、以及 DocDB 存储引擎的设计对分布式存储开发者有直接参考意义。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/yugabytedb.sql) | PG 兼容分布式(YSQL)，HASH/RANGE 分片，Tablet 自动分裂 |
| [改表](../ddl/alter-table/yugabytedb.sql) | PG 兼容 ALTER，在线 Schema 变更 |
| [索引](../ddl/indexes/yugabytedb.sql) | LSM 分布式索引(PG 兼容语法)，COVERING(=INCLUDE) |
| [约束](../ddl/constraints/yugabytedb.sql) | PK/FK/CHECK/UNIQUE(PG 兼容)，分布式强一致 |
| [视图](../ddl/views/yugabytedb.sql) | 普通视图(PG 兼容)，物化视图支持 |
| [序列与自增](../ddl/sequences/yugabytedb.sql) | SERIAL/IDENTITY/SEQUENCE(PG 兼容)，分布式序列 |
| [数据库/Schema/用户](../ddl/users-databases/yugabytedb.sql) | PG 兼容权限模型，Tablet Server 集群 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/yugabytedb.sql) | EXECUTE(PL/pgSQL 兼容) |
| [错误处理](../advanced/error-handling/yugabytedb.sql) | EXCEPTION WHEN(PL/pgSQL 兼容) |
| [执行计划](../advanced/explain/yugabytedb.sql) | EXPLAIN ANALYZE(PG 兼容)+Dist 分布式信息 |
| [锁机制](../advanced/locking/yugabytedb.sql) | 行级锁+分布式锁(Raft)，Wait-on-Conflict(2.20+) |
| [分区](../advanced/partitioning/yugabytedb.sql) | PARTITION BY(PG 兼容)+SPLIT INTO TABLETS 分片 |
| [权限](../advanced/permissions/yugabytedb.sql) | PG 兼容 RBAC，行级安全(RLS) |
| [存储过程](../advanced/stored-procedures/yugabytedb.sql) | PL/pgSQL(PG 兼容) |
| [临时表](../advanced/temp-tables/yugabytedb.sql) | TEMPORARY TABLE(PG 兼容) |
| [事务](../advanced/transactions/yugabytedb.sql) | 分布式 ACID(Raft+MVCC)，Snapshot/Serializable 隔离 |
| [触发器](../advanced/triggers/yugabytedb.sql) | PG 兼容触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/yugabytedb.sql) | DELETE/RETURNING(PG 兼容)，分布式并行 |
| [插入](../dml/insert/yugabytedb.sql) | INSERT/RETURNING(PG 兼容)，ON CONFLICT |
| [更新](../dml/update/yugabytedb.sql) | UPDATE/RETURNING(PG 兼容)，分布式事务 |
| [Upsert](../dml/upsert/yugabytedb.sql) | ON CONFLICT(PG 兼容)，分布式 Upsert |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/yugabytedb.sql) | PG 兼容聚合，分布式聚合下推 |
| [条件函数](../functions/conditional/yugabytedb.sql) | CASE/COALESCE(PG 兼容) |
| [日期函数](../functions/date-functions/yugabytedb.sql) | PG 兼容日期函数 |
| [数学函数](../functions/math-functions/yugabytedb.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/yugabytedb.sql) | PG 兼容字符串函数，|| 拼接 |
| [类型转换](../functions/type-conversion/yugabytedb.sql) | CAST/::(PG 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/yugabytedb.sql) | WITH+递归 CTE(PG 兼容) |
| [全文搜索](../query/full-text-search/yugabytedb.sql) | tsvector/tsquery(PG 兼容)，GIN 索引 |
| [连接查询](../query/joins/yugabytedb.sql) | PG 兼容 JOIN，Batched Nested Loop 分布式优化 |
| [分页](../query/pagination/yugabytedb.sql) | LIMIT/OFFSET(PG 兼容)，Keyset 分页推荐 |
| [行列转换](../query/pivot-unpivot/yugabytedb.sql) | crosstab(PG 兼容) |
| [集合操作](../query/set-operations/yugabytedb.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/yugabytedb.sql) | 关联子查询(PG 兼容)，分布式优化 |
| [窗口函数](../query/window-functions/yugabytedb.sql) | 完整窗口函数(PG 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/yugabytedb.sql) | generate_series(PG 兼容) |
| [去重](../scenarios/deduplication/yugabytedb.sql) | DISTINCT ON/ROW_NUMBER(PG 兼容) |
| [区间检测](../scenarios/gap-detection/yugabytedb.sql) | generate_series+窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/yugabytedb.sql) | 递归 CTE(PG 兼容) |
| [JSON 展开](../scenarios/json-flatten/yugabytedb.sql) | json_each/json_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/yugabytedb.sql) | PG 高度兼容，分布式分片+Raft 一致性是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/yugabytedb.sql) | ROW_NUMBER+LIMIT(PG 兼容) |
| [累计求和](../scenarios/running-total/yugabytedb.sql) | SUM() OVER(PG 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/yugabytedb.sql) | ON CONFLICT(PG 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/yugabytedb.sql) | string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/yugabytedb.sql) | 完整窗口函数(PG 兼容)，分布式排序 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/yugabytedb.sql) | ARRAY/复合类型(PG 兼容) |
| [日期时间](../types/datetime/yugabytedb.sql) | DATE/TIMESTAMP/INTERVAL(PG 兼容) |
| [JSON](../types/json/yugabytedb.sql) | JSON/JSONB+GIN 索引(PG 兼容) |
| [数值类型](../types/numeric/yugabytedb.sql) | INT/BIGINT/NUMERIC/FLOAT(PG 兼容) |
| [字符串类型](../types/string/yugabytedb.sql) | TEXT/VARCHAR(PG 兼容)，UTF-8 |
