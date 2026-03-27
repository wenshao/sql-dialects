# TimescaleDB

**分类**: 时序数据库（PostgreSQL 扩展）
**文件数**: 51 个 SQL 文件
**总行数**: 4382 行

## 概述与定位

TimescaleDB 是 Timescale 公司基于 PostgreSQL 扩展机制开发的时序数据库，以 PostgreSQL 扩展（Extension）的形式安装，完整保留 PostgreSQL 的全部 SQL 能力。它定位于 IoT 监控、DevOps 可观测性、金融行情等需要高效时序数据处理的场景。与专有时序数据库不同，TimescaleDB 的核心优势是"时序能力 + 完整 SQL"——用户不需要学习新的查询语言或放弃关系型数据库的事务和 JOIN 能力。

## 历史与演进

- **2017 年**：Timescale 公司成立并开源 TimescaleDB，作为 PG 扩展发布。
- **2018 年**：引入 Continuous Aggregates（持续聚合物化视图）。
- **2019 年**：支持多节点分布式部署（Multi-Node，后续已弃用）。
- **2020 年**：引入原生列式压缩（Compression），大幅降低存储成本。
- **2021 年**：推出 Timescale Cloud 托管服务和数据分层（Data Tiering）。
- **2022 年**：Continuous Aggregates 支持实时刷新和层级嵌套。
- **2023-2025 年**：引入 Hypercore 列存引擎、自动压缩策略优化和向量搜索能力。

## 核心设计思路

TimescaleDB 的核心抽象是 **hypertable**——一个对用户透明的自动分区表。创建 hypertable 后，数据按时间维度自动分成多个 chunk（时间分片），每个 chunk 是一个独立的 PG 表。查询时 TimescaleDB 利用 chunk 排除（类似分区裁剪）只扫描相关时间段。这种设计使插入性能不会随数据量增长而退化。由于完全基于 PG 扩展 API，所有 PG 功能（JOIN、CTE、窗口函数、事务、扩展生态）均可直接使用。

## 独特特色

- **hypertable**：`SELECT create_hypertable('metrics', 'time')` 将普通表转为自动按时间分区的超级表。
- **time_bucket()**：`time_bucket('5 minutes', time)` 灵活的时间桶聚合函数，替代 `date_trunc` 支持任意间隔。
- **Continuous Aggregates**：`CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)` 自动增量刷新的物化视图。
- **原生压缩**：`ALTER TABLE metrics SET (timescaledb.compress)` 列式压缩旧数据，压缩率可达 90%+。
- **数据保留策略**：`SELECT add_retention_policy('metrics', INTERVAL '90 days')` 自动删除过期数据。
- **数据分层**：将冷数据自动迁移到低成本对象存储。
- **完整 PG 兼容**：JOIN、子查询、CTE、窗口函数、PostGIS 等全部可用。

## 已知不足

- 仅支持时间维度作为主分区维度，非时序场景收益有限。
- 压缩后的 chunk 不支持直接 UPDATE/DELETE（需先解压）。
- 多节点分布式方案已弃用，水平扩展依赖 Timescale Cloud 的方案。
- Continuous Aggregates 在高基数分组场景下刷新开销较大。
- 与 PG 大版本升级的兼容性需要等待扩展适配。
- 社区版（Apache 2.0）和企业版（Timescale License）功能有差异。

## 对引擎开发者的参考价值

TimescaleDB 展示了如何在不修改数据库内核的情况下通过扩展机制实现专有场景优化——这是 PostgreSQL 扩展生态的极致体现。hypertable 的自动分区和 chunk 管理设计、Continuous Aggregates 的增量物化视图实现、以及列式压缩在 PG 行存引擎上的叠加方式对扩展开发者有直接参考价值。time_bucket 函数的设计也启发了其他数据库的时间聚合函数实现。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/timescaledb.sql) | PG 扩展(时序数据库)，Hypertable 自动分片，CREATE+CHUNK |
| [改表](../ddl/alter-table/timescaledb.sql) | PG 兼容 ALTER，Hypertable 透明管理 |
| [索引](../ddl/indexes/timescaledb.sql) | B-tree/GIN/GiST(PG 兼容)，时间列自动索引 |
| [约束](../ddl/constraints/timescaledb.sql) | PK/FK/CHECK(PG 兼容)，分布式唯一约束需含时间列 |
| [视图](../ddl/views/timescaledb.sql) | Continuous Aggregate 连续聚合(独有)，增量维护 |
| [序列与自增](../ddl/sequences/timescaledb.sql) | SERIAL/IDENTITY(PG 兼容) |
| [数据库/Schema/用户](../ddl/users-databases/timescaledb.sql) | PG 兼容权限，Hypertable 透明集成 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/timescaledb.sql) | EXECUTE(PL/pgSQL 兼容) |
| [错误处理](../advanced/error-handling/timescaledb.sql) | EXCEPTION WHEN(PL/pgSQL 兼容) |
| [执行计划](../advanced/explain/timescaledb.sql) | EXPLAIN ANALYZE(PG 兼容)，Chunk 裁剪信息 |
| [锁机制](../advanced/locking/timescaledb.sql) | PG 兼容锁，Chunk 级别并发 |
| [分区](../advanced/partitioning/timescaledb.sql) | Hypertable 自动按时间分 Chunk(核心功能)，空间分区可选 |
| [权限](../advanced/permissions/timescaledb.sql) | PG 兼容 RBAC |
| [存储过程](../advanced/stored-procedures/timescaledb.sql) | PL/pgSQL(PG 兼容)+Jobs 定时任务(独有) |
| [临时表](../advanced/temp-tables/timescaledb.sql) | TEMPORARY TABLE(PG 兼容) |
| [事务](../advanced/transactions/timescaledb.sql) | ACID(PG 兼容)，DDL 事务性 |
| [触发器](../advanced/triggers/timescaledb.sql) | PG 兼容触发器，Chunk 级别执行 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/timescaledb.sql) | DELETE(PG 兼容)+drop_chunks() 按时间范围高效删除(独有) |
| [插入](../dml/insert/timescaledb.sql) | INSERT(PG 兼容)，Hypertable 自动路由到 Chunk |
| [更新](../dml/update/timescaledb.sql) | UPDATE(PG 兼容) |
| [Upsert](../dml/upsert/timescaledb.sql) | ON CONFLICT(PG 兼容)，时序 Upsert 常见 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/timescaledb.sql) | PG 兼容+time_bucket 时间桶聚合(独有核心函数) |
| [条件函数](../functions/conditional/timescaledb.sql) | CASE/COALESCE(PG 兼容) |
| [日期函数](../functions/date-functions/timescaledb.sql) | PG 兼容+time_bucket/time_bucket_gapfill(独有) |
| [数学函数](../functions/math-functions/timescaledb.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/timescaledb.sql) | PG 兼容字符串函数 |
| [类型转换](../functions/type-conversion/timescaledb.sql) | CAST/::(PG 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/timescaledb.sql) | WITH+递归 CTE(PG 兼容) |
| [全文搜索](../query/full-text-search/timescaledb.sql) | tsvector/tsquery(PG 兼容) |
| [连接查询](../query/joins/timescaledb.sql) | PG 兼容 JOIN，Hypertable JOIN 优化 |
| [分页](../query/pagination/timescaledb.sql) | LIMIT/OFFSET(PG 兼容) |
| [行列转换](../query/pivot-unpivot/timescaledb.sql) | crosstab(PG 兼容) |
| [集合操作](../query/set-operations/timescaledb.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/timescaledb.sql) | 关联子查询(PG 兼容) |
| [窗口函数](../query/window-functions/timescaledb.sql) | 完整窗口函数(PG 兼容)，时序分析增强 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/timescaledb.sql) | time_bucket_gapfill+locf/interpolate(独有) 原生填充 |
| [去重](../scenarios/deduplication/timescaledb.sql) | ROW_NUMBER+CTE(PG 兼容) |
| [区间检测](../scenarios/gap-detection/timescaledb.sql) | time_bucket_gapfill 原生检测(独有) |
| [层级查询](../scenarios/hierarchical-query/timescaledb.sql) | 递归 CTE(PG 兼容) |
| [JSON 展开](../scenarios/json-flatten/timescaledb.sql) | json_each/json_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/timescaledb.sql) | PG 完全兼容+Hypertable+Continuous Aggregate 是核心增值 |
| [TopN 查询](../scenarios/ranking-top-n/timescaledb.sql) | ROW_NUMBER+LIMIT(PG 兼容) |
| [累计求和](../scenarios/running-total/timescaledb.sql) | SUM() OVER(PG 兼容)，时序累计 |
| [缓慢变化维](../scenarios/slowly-changing-dim/timescaledb.sql) | ON CONFLICT(PG 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/timescaledb.sql) | string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/timescaledb.sql) | PG 兼容+time_bucket 时间桶分析(独有优势) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/timescaledb.sql) | ARRAY/复合类型(PG 兼容) |
| [日期时间](../types/datetime/timescaledb.sql) | TIMESTAMP/TIMESTAMPTZ(PG 兼容)，时序核心类型 |
| [JSON](../types/json/timescaledb.sql) | JSON/JSONB(PG 兼容)，GIN 索引 |
| [数值类型](../types/numeric/timescaledb.sql) | INT/BIGINT/NUMERIC/FLOAT(PG 兼容) |
| [字符串类型](../types/string/timescaledb.sql) | TEXT/VARCHAR(PG 兼容) |
