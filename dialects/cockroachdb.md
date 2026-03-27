# CockroachDB

**分类**: 分布式数据库（兼容 PostgreSQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4696 行

## 概述与定位

CockroachDB 是 Cockroach Labs 于 2015 年开源的分布式 SQL 数据库，兼容 PostgreSQL 协议和大部分语法。其命名源自蟑螂的生存韧性——设计目标是构建一个"杀不死"的数据库：自动分片、自动故障恢复、跨地域强一致。CockroachDB 定位于需要全球部署、零停机和强一致事务保证的云原生应用场景。

## 历史与演进

- **2014 年**：前 Google 工程师（曾参与 Spanner 项目）创立 Cockroach Labs。
- **2015 年**：项目开源，基于 Go 语言实现，底层存储采用 RocksDB。
- **2017 年**：1.0 GA，支持分布式 ACID 事务和自动负载均衡。
- **2019 年**：19.x 引入 CDC（Change Data Capture）和成本优化器。
- **2020 年**：20.x 推出多区域（Multi-Region）抽象，简化全球部署。
- **2021 年**：21.x 引入 REGIONAL BY ROW 行级地域策略。
- **2022 年**：22.x 切换底层存储引擎为 Pebble（自研 Go LSM 引擎）。
- **2023-2025 年**：23.x/24.x 持续增强 PG 兼容性、物理集群复制、AI 向量能力。

## 核心设计思路

CockroachDB 将数据存储为有序 KV 对，按 Range（默认 512 MB）自动分片。每个 Range 通过 Raft 共识协议维护多副本。事务模型基于 MVCC + 分布式时间戳排序，**默认使用 SERIALIZABLE 隔离级别**（这是其区别于多数分布式数据库的显著特征）。混合逻辑时钟（HLC）提供跨节点的因果一致时间戳。SQL 层兼容 PostgreSQL 线协议，使用基于成本的优化器生成分布式执行计划。

## 独特特色

- **默认 SERIALIZABLE**：开箱即用的最严格隔离级别，避免所有读写异常。
- **unique_rowid()**：内置函数生成全局唯一、大致有序的 ID，替代自增序列避免热点。
- **CHANGEFEED**：原生 CDC 能力，`CREATE CHANGEFEED FOR table INTO 'kafka://...'` 实现实时数据流出。
- **多区域抽象**：`ALTER DATABASE SET PRIMARY REGION`、`REGIONAL BY ROW`、`GLOBAL TABLE` 等声明式地域策略。
- **自动 Range 分裂/合并/再平衡**：无需人工干预分片管理。
- **AS OF SYSTEM TIME**：支持历史时间点读取，用于无锁备份和分析查询。
- **Pebble 存储引擎**：自研 Go 实现的 LSM-Tree 引擎，消除了 CGo 跨语言开销。

## 已知不足

- 严格的 SERIALIZABLE 隔离在高并发写冲突场景下事务重试率较高。
- 与 PostgreSQL 的兼容性虽在持续改进，但存储过程（PL/pgSQL）支持仍在完善阶段。
- 跨地域部署时写延迟受限于多数派提交的 RTT。
- 不支持 PostgreSQL 扩展生态（如 PostGIS 等，需使用内置空间功能）。
- 批量导入性能相比专有分析型数据库有差距。
- 许可证从 Apache 2.0 改为 BSL（Business Source License），影响部分开源使用场景。

## 对引擎开发者的参考价值

CockroachDB 的工程实践展示了如何在分布式环境中实现 SERIALIZABLE 隔离（并发控制与时间戳排序的平衡）、基于 HLC 的分布式时钟方案、以及声明式多区域数据放置的抽象设计。其从 RocksDB 迁移到自研 Pebble 引擎的决策过程也为存储引擎选型提供了重要经验。CHANGEFEED 的实现展示了如何将 CDC 作为数据库原生能力提供。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/cockroachdb.sql) | PG 兼容语法，分布式表自动分片(Range)，SERIAL→unique_rowid() |
| [改表](../ddl/alter-table/cockroachdb.sql) | 在线 Schema 变更(无锁)，分布式 DDL 原子性 |
| [索引](../ddl/indexes/cockroachdb.sql) | 分布式 LSM 索引，STORING 覆盖列，部分索引(21.1+) |
| [约束](../ddl/constraints/cockroachdb.sql) | PK/FK/CHECK/UNIQUE 标准支持，分布式约束一致性 |
| [视图](../ddl/views/cockroachdb.sql) | 普通视图支持，无物化视图 |
| [序列与自增](../ddl/sequences/cockroachdb.sql) | SERIAL→unique_rowid()，SEQUENCE 支持但分布式性能差 |
| [数据库/Schema/用户](../ddl/users-databases/cockroachdb.sql) | PG 兼容权限模型，多租户 Cluster 级隔离 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/cockroachdb.sql) | PL/pgSQL(23.1+) 有限支持，EXECUTE 动态 SQL |
| [错误处理](../advanced/error-handling/cockroachdb.sql) | PG 兼容 EXCEPTION 处理(有限)，事务自动重试 |
| [执行计划](../advanced/explain/cockroachdb.sql) | EXPLAIN ANALYZE (DISTSQL) 分布式执行计划 |
| [锁机制](../advanced/locking/cockroachdb.sql) | 乐观事务+悲观锁(可选)，分布式锁管理，无间隙锁 |
| [分区](../advanced/partitioning/cockroachdb.sql) | PARTITION BY 地理分区(Geo-Partitioning)，Region 级数据放置 |
| [权限](../advanced/permissions/cockroachdb.sql) | PG 兼容 RBAC，GRANT/REVOKE 标准语法 |
| [存储过程](../advanced/stored-procedures/cockroachdb.sql) | PL/pgSQL(23.1+) 有限支持，UDF 支持 |
| [临时表](../advanced/temp-tables/cockroachdb.sql) | TEMPORARY TABLE 支持，会话级 |
| [事务](../advanced/transactions/cockroachdb.sql) | 分布式 ACID(Serializable 默认)，自动重试机制 |
| [触发器](../advanced/triggers/cockroachdb.sql) | 不支持触发器，用 CDC(Change Data Capture) 替代 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/cockroachdb.sql) | DELETE 标准，分布式删除自动并行 |
| [插入](../dml/insert/cockroachdb.sql) | INSERT+ON CONFLICT(PG 兼容)，IMPORT 批量导入 |
| [更新](../dml/update/cockroachdb.sql) | UPDATE 标准(PG 兼容)，分布式更新 |
| [Upsert](../dml/upsert/cockroachdb.sql) | UPSERT 简写+ON CONFLICT DO UPDATE(PG 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/cockroachdb.sql) | PG 兼容聚合，分布式聚合自动下推 |
| [条件函数](../functions/conditional/cockroachdb.sql) | CASE/COALESCE/NULLIF(PG 兼容) |
| [日期函数](../functions/date-functions/cockroachdb.sql) | PG 兼容日期函数，分布式时钟(HLC)保证时序 |
| [数学函数](../functions/math-functions/cockroachdb.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/cockroachdb.sql) | PG 兼容字符串函数，|| 拼接 |
| [类型转换](../functions/type-conversion/cockroachdb.sql) | CAST/:: 运算符(PG 兼容)，严格类型 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/cockroachdb.sql) | 递归 CTE 支持(PG 兼容)，WITH 标准 |
| [全文搜索](../query/full-text-search/cockroachdb.sql) | 全文搜索索引(20.2+)，GIN 索引支持 |
| [连接查询](../query/joins/cockroachdb.sql) | Lookup/Hash/Merge JOIN，分布式 JOIN 自动优化 |
| [分页](../query/pagination/cockroachdb.sql) | LIMIT/OFFSET(PG 兼容)，AS OF SYSTEM TIME 减少争用 |
| [行列转换](../query/pivot-unpivot/cockroachdb.sql) | 无原生 PIVOT，用 CASE+GROUP BY |
| [集合操作](../query/set-operations/cockroachdb.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/cockroachdb.sql) | 关联子查询+EXISTS/IN(PG 兼容)，分布式优化 |
| [窗口函数](../query/window-functions/cockroachdb.sql) | 完整窗口函数(PG 兼容)，分布式排序 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/cockroachdb.sql) | generate_series(PG 兼容) 生成日期序列 |
| [去重](../scenarios/deduplication/cockroachdb.sql) | ROW_NUMBER+CTE(PG 兼容)，DISTINCT ON 支持 |
| [区间检测](../scenarios/gap-detection/cockroachdb.sql) | generate_series+窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/cockroachdb.sql) | 递归 CTE(PG 兼容) |
| [JSON 展开](../scenarios/json-flatten/cockroachdb.sql) | JSONB+GIN 索引(PG 兼容)，json_each/json_array_elements |
| [迁移速查](../scenarios/migration-cheatsheet/cockroachdb.sql) | PG 兼容但分布式事务语义有差异，SERIAL 行为不同 |
| [TopN 查询](../scenarios/ranking-top-n/cockroachdb.sql) | ROW_NUMBER/RANK(PG 兼容)，LIMIT 标准 |
| [累计求和](../scenarios/running-total/cockroachdb.sql) | SUM() OVER(PG 兼容)，分布式窗口函数 |
| [缓慢变化维](../scenarios/slowly-changing-dim/cockroachdb.sql) | UPSERT 简写方便，无 MERGE 语句 |
| [字符串拆分](../scenarios/string-split-to-rows/cockroachdb.sql) | regexp_split_to_table/string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/cockroachdb.sql) | 完整窗口函数(PG 兼容)，分布式排序开销大 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/cockroachdb.sql) | ARRAY 类型(PG 兼容)，无自定义复合类型 |
| [日期时间](../types/datetime/cockroachdb.sql) | TIMESTAMP/DATE/TIME/INTERVAL(PG 兼容)，HLC 分布式时钟 |
| [JSON](../types/json/cockroachdb.sql) | JSONB+GIN 索引(PG 兼容)，JSON 路径查询 |
| [数值类型](../types/numeric/cockroachdb.sql) | INT/FLOAT/DECIMAL(PG 兼容)，无 UNSIGNED |
| [字符串类型](../types/string/cockroachdb.sql) | STRING/VARCHAR/TEXT(PG 兼容)，UTF-8 默认 |
